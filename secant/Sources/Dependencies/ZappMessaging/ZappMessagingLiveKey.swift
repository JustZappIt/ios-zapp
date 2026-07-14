//
//  ZappMessagingLiveKey.swift
//  Zapp
//
//  The worklet lifecycle owner — iOS's answer to Android's ChatBootstrap.
//
//  Android boots the worklet reactively, off a `Flow<PersistableWallet?>` that
//  emits null and then a wallet, which is why it can start on the welcome screen
//  before a wallet exists. iOS has no such publisher (WalletStorageClient is
//  synchronous-throwing), so that shape cannot be transcribed. Instead this is
//  edge-triggered from Root's `.initializationSuccessfullyDone`, which fires
//  after the seed has been read on both the new-wallet and existing-wallet paths.
//  That is strictly safer: the worklet never boots without a wallet.
//

@preconcurrency import Combine
import ComposableArchitecture
import Foundation
import ZappMessaging

extension ZappMessagingClient: DependencyKey {
    static let liveValue: ZappMessagingClient = Self.live()

    static func live() -> Self {
        let impl = ZappMessagingImpl()

        return ZappMessagingClient(
            start: { impl.start() },
            suspend: { impl.suspend() },
            resume: { impl.resume() },
            wipe: { await impl.wipe() },
            setDisplayName: { impl.setDisplayName($0) },
            retryIdentityDerivation: { impl.retryIdentityDerivation() },
            updateDisplayName: { try await impl.updateDisplayName($0) },
            stateStream: { impl.stateSubject.eraseToAnyPublisher() },
            latestState: { impl.stateSubject.value },
            conversationsStream: { impl.conversationsSubject.eraseToAnyPublisher() },
            refreshConversations: { try await impl.refreshConversations() },
            messages: { try await impl.messages(conversationId: $0, limit: $1) },
            sendMessage: { try await impl.sendMessage(conversationId: $0, content: $1) },
            markRead: { try await impl.markRead(conversationId: $0) },
            messageReceivedStream: { impl.messageReceivedSubject.eraseToAnyPublisher() },
            setActiveConversation: { impl.setActiveConversation($0) }
        )
    }
}

/// Owns the `ZappMessagingSDK` for the process lifetime.
///
/// `@unchecked Sendable` follows the house pattern (`ShieldingProcessorImpl`):
/// the `@Dependency` wrappers are task-local lookups and the Combine subjects are
/// reference-counted Sendable storage. The SDK itself is `@MainActor`, so every
/// hop into it goes through `Task { @MainActor in ... }`.
private final class ZappMessagingImpl: @unchecked Sendable {
    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.walletStorage) var walletStorage

    let stateSubject = CurrentValueSubject<ZappMessagingState, Never>(ZappMessagingState())
    let conversationsSubject = CurrentValueSubject<[ZMConversation], Never>([])
    let messageReceivedSubject = PassthroughSubject<ZMMessage, Never>()

    /// Created lazily: constructing it resolves the data dir, which touches the
    /// filesystem, and `liveValue` is built eagerly at first dependency access.
    private var sdk: ZappMessagingSDK?
    private var cancellables = Set<AnyCancellable>()

    private let lock = NSLock()
    private var hasStarted = false
    private var pendingDisplayName: String?
    private var activeConversationId: String?
    private var unreadCounts: [String: Int] = [:]

    // MARK: - Lifecycle

    func start() {
        lock.lock()
        guard !hasStarted else {
            lock.unlock()
            return
        }
        hasStarted = true
        lock.unlock()

        mutate { $0.phase = .initializing }

        Task { @MainActor in
            do {
                let sdk = try ZappMessagingSDK(config: ZappMessagingBuildConfig.config())
                self.sdk = sdk
                self.observe(sdk)

                try await sdk.initialize()

                if let identity = sdk.identity {
                    self.mutate {
                        $0.identity = identity
                        $0.phase = .ready
                    }
                    try? await sdk.refreshConversations()
                    self.conversationsSubject.send(sdk.conversations)
                } else {
                    // A missing identity is the normal first-run outcome. The user
                    // has to pick a name before we can derive one.
                    self.mutate { $0.phase = .needsIdentity }
                    self.deriveIfPossible()
                }
            } catch {
                LoggerProxy.event("ZappMessaging: worklet boot failed: \(error)")
                self.mutate { $0.phase = .failed(Self.errorCode(error)) }
                self.lock.withLock { self.hasStarted = false }
            }
        }
    }

    func suspend() {
        guard let sdk else { return }
        Task { @MainActor in await sdk.suspend() }
    }

    func resume() {
        guard let sdk else { return }
        Task { @MainActor in await sdk.resume() }
    }

    /// Stop the worklet, then delete its store. In that order — a running worklet
    /// still holds rocksdb's files open.
    func wipe() async {
        if let sdk {
            await sdk.shutdown()
        }

        self.sdk = nil
        cancellables.removeAll()
        lock.withLock {
            hasStarted = false
            pendingDisplayName = nil
            activeConversationId = nil
            unreadCounts = [:]
        }

        if let container = try? ZappMessagingConfig.defaultDataDir() {
            let store = ZappMessagingConfig.storeDirectory(inContainer: container)
            try? FileManager.default.removeItem(at: store)
        }

        stateSubject.send(ZappMessagingState())
        conversationsSubject.send([])
    }

    // MARK: - Identity

    func setDisplayName(_ name: String) {
        lock.withLock { pendingDisplayName = name }
        mutate { $0.identityErrorCode = nil }
        deriveIfPossible()
    }

    func retryIdentityDerivation() {
        guard stateSubject.value.phase != .deriving else { return }
        mutate { $0.identityErrorCode = nil }
        deriveIfPossible()
    }

    func updateDisplayName(_ name: String) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        try await sdk.updateDisplayName(name)
        if let identity = await sdk.identity {
            mutate { $0.identity = identity }
        }
    }

    /// Derive only when the worklet is up, no identity exists, and a name has been
    /// chosen. Equivalent to Android's 5-way `combine` gate, minus the wallet
    /// stream it has and we do not.
    private func deriveIfPossible() {
        guard let sdk else { return }

        let phase = stateSubject.value.phase
        guard phase == .needsIdentity || phase == .ready else { return }
        guard stateSubject.value.identity == nil else { return }

        guard let displayName = lock.withLock({ pendingDisplayName }), !displayName.isEmpty else {
            return
        }

        mutate { $0.phase = .deriving }

        Task { @MainActor in
            do {
                let storedWallet = try self.walletStorage.exportWallet()

                // The chat IPC wants the 24-word PHRASE, not the derived seed
                // bytes that ZcashLightClientKit takes. Passing bytes fails.
                let seedPhrase = storedWallet.seedPhrase.value()

                let identity = try await sdk.restoreFromSeedPhrase(seedPhrase, displayName: displayName)

                self.lock.withLock { self.pendingDisplayName = nil }
                self.mutate {
                    $0.identity = identity
                    $0.identityErrorCode = nil
                    $0.phase = .ready
                }

                try? await sdk.refreshConversations()
                self.conversationsSubject.send(sdk.conversations)
            } catch {
                LoggerProxy.event("ZappMessaging: identity derivation failed: \(error)")
                self.mutate {
                    $0.identityErrorCode = Self.errorCode(error)
                    $0.phase = .needsIdentity
                }
            }
        }
    }

    // MARK: - Conversations & messages

    func refreshConversations() async throws {
        guard let sdk else { throw ZMError.notInitialized }
        try await sdk.refreshConversations()
        conversationsSubject.send(await sdk.conversations)
    }

    func messages(conversationId: String, limit: Int) async throws -> [ZMMessage] {
        guard let sdk else { throw ZMError.notInitialized }
        return try await sdk.getMessages(conversationId: conversationId, limit: limit)
    }

    func sendMessage(conversationId: String, content: String) async throws -> ZMMessage {
        guard let sdk else { throw ZMError.notInitialized }
        return try await sdk.sendMessage(conversationId: conversationId, content: content)
    }

    func markRead(conversationId: String) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        try await sdk.markRead(conversationId: conversationId)
        clearUnread(for: conversationId)
    }

    func setActiveConversation(_ conversationId: String?) {
        lock.withLock { activeConversationId = conversationId }
        if let conversationId {
            clearUnread(for: conversationId)
        }
    }

    // MARK: - Event wiring

    @MainActor
    private func observe(_ sdk: ZappMessagingSDK) {
        sdk.messageReceived
            .receive(on: mainQueue)
            .sink { [weak self] _, message in
                guard let self else { return }
                self.messageReceivedSubject.send(message)
                self.countUnread(message)
                Task { try? await self.refreshConversations() }
            }
            .store(in: &cancellables)

        sdk.$isOnline
            .receive(on: mainQueue)
            .sink { [weak self] online in self?.mutate { $0.isOnline = online } }
            .store(in: &cancellables)

        sdk.$peerCount
            .receive(on: mainQueue)
            .sink { [weak self] count in self?.mutate { $0.peerCount = count } }
            .store(in: &cancellables)

        sdk.$dhtHealth
            .receive(on: mainQueue)
            .sink { [weak self] health in self?.mutate { $0.dhtHealth = health } }
            .store(in: &cancellables)
    }

    /// Unread is counted app-side, not read off the wire — the core never sends
    /// an `unreadCount` and `ZMConversation` never carries one.
    private func countUnread(_ message: ZMMessage) {
        guard !message.isFromMe else { return }
        guard lock.withLock({ activeConversationId }) != message.conversationId else { return }

        let total: Int = lock.withLock {
            unreadCounts[message.conversationId, default: 0] += 1
            return unreadCounts.values.reduce(0, +)
        }
        mutate { $0.totalUnreadCount = total }
    }

    private func clearUnread(for conversationId: String) {
        let total: Int = lock.withLock {
            unreadCounts[conversationId] = nil
            return unreadCounts.values.reduce(0, +)
        }
        mutate { $0.totalUnreadCount = total }
    }

    // MARK: - Helpers

    private func mutate(_ change: (inout ZappMessagingState) -> Void) {
        var state = stateSubject.value
        change(&state)
        guard state != stateSubject.value else { return }
        stateSubject.send(state)
    }

    /// Stable codes for the setup screen's error line, mirroring Android's
    /// SetupErrorCode. Never contains the seed, the key or the name.
    private static func errorCode(_ error: Error) -> String {
        guard let zmError = error as? ZMError else {
            return (error as NSError).domain
        }

        switch zmError {
        case .notInitialized:       return "SDK_NOT_READY"
        case .ipcTimeout:           return "IPC_TIMEOUT"
        case .ipcError:             return "IPC_ERROR"
        case .workletError:         return "WORKLET_ERROR"
        case .invalidData:          return "BAD_RESPONSE"
        case .invalidSeedPhrase:    return "INVALID_SEED"
        case .identityNotFound:     return "NO_IDENTITY"
        default:                    return "UNKNOWN"
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
