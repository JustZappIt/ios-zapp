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
import UIKit
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
            syncPushNotifications: { await impl.syncPushNotifications() },
            connectionDetails: { try await impl.connectionDetails() },
            createDirectConversation: { try await impl.createDirectConversation(publicKey: $0, displayName: $1) },
            createGroup: { try await impl.createGroup(name: $0, participantKeys: $1) },
            renameGroup: { try await impl.renameGroup(conversationId: $0, name: $1) },
            addMember: { try await impl.addMember(conversationId: $0, publicKey: $1, displayName: $2) },
            leaveConversation: { try await impl.leaveConversation($0) },
            removeConversation: { try await impl.removeConversation($0) },
            hasLeftDirectConversation: { try await impl.hasLeftDirectConversation(publicKey: $0) },
            messages: { try await impl.messages(conversationId: $0, limit: $1) },
            sendMessage: { try await impl.sendMessage(conversationId: $0, content: $1, replyTo: $2) },
            sendMedia: { try await impl.sendMedia(conversationId: $0, mediaPath: $1, contentType: $2, caption: $3, thumbnailData: $4) },
            markRead: { try await impl.markRead(conversationId: $0) },
            messageStatusStream: { impl.messageStatusSubject.eraseToAnyPublisher() },
            mediaProgressStream: { impl.mediaProgressSubject.eraseToAnyPublisher() },
            mediaCompleteStream: { impl.mediaCompleteSubject.eraseToAnyPublisher() },
            setReadReceiptsEnabled: { try await impl.setReadReceiptsEnabled($0) },
            setPresenceVisible: { try await impl.setPresenceVisible($0) },
            messageReceivedStream: { impl.messageReceivedSubject.eraseToAnyPublisher() },
            setActiveConversation: { impl.setActiveConversation($0) },
            setBlockedKeys: { impl.setBlockedKeys($0) }
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
    @Dependency(\.userDefaults) var userDefaults
    @Dependency(\.walletStorage) var walletStorage

    private enum PrefKey {
        static let readReceipts = "zappChat.readReceiptsEnabled"
        static let presence = "zappChat.presenceVisible"
    }

    let stateSubject = CurrentValueSubject<ZappMessagingState, Never>(ZappMessagingState())
    let conversationsSubject = CurrentValueSubject<[ZMConversation], Never>([])
    let messageReceivedSubject = PassthroughSubject<ZMMessage, Never>()
    let messageStatusSubject = PassthroughSubject<(messageId: String, conversationId: String, status: String), Never>()
    let mediaProgressSubject = PassthroughSubject<(mediaId: String, progress: Double), Never>()
    let mediaCompleteSubject = PassthroughSubject<(mediaId: String, filePath: String), Never>()

    /// Created lazily: constructing it resolves the data dir, which touches the
    /// filesystem, and `liveValue` is built eagerly at first dependency access.
    private var sdk: ZappMessagingSDK?
    private var cancellables = Set<AnyCancellable>()

    private let lock = NSLock()
    private var hasStarted = false
    private var pendingDisplayName: String?
    private var activeConversationId: String?
    private var unreadCounts: [String: Int] = [:]
    private var blockedKeys: Set<String> = []
    private var lifecycleRequestSequence: UInt64 = 0
    private let lifecycle = MessagingLifecycleOwner()

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
                await self.lifecycle.install(
                    suspend: { await sdk.suspend() },
                    resume: { await sdk.resume() }
                )

                if let identity = sdk.identity {
                    await self.reassertPrivacySettings(sdk)
                    self.mutate {
                        $0.identity = identity
                        $0.phase = .ready
                    }
                    do {
                        try await self.refreshConversations()
                    } catch {
                        // Identity is still usable. The structured failure remains visible
                        // from the network sheet and can be retried there.
                    }
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
        requestLifecycleState(.background)
    }

    func resume() {
        requestLifecycleState(.foreground)
    }

    /// Stop the worklet, then delete its store. In that order — a running worklet
    /// still holds rocksdb's files open.
    func wipe() async {
        if let sdk {
            await sdk.shutdown()
        }
        await lifecycle.uninstall()

        self.sdk = nil
        cancellables.removeAll()
        lock.withLock {
            hasStarted = false
            pendingDisplayName = nil
            activeConversationId = nil
            unreadCounts = [:]
        }

        do {
            let container = try ZappMessagingConfig.defaultDataDir()
            let store = ZappMessagingConfig.storeDirectory(inContainer: container)
            if FileManager.default.fileExists(atPath: store.path) {
                try FileManager.default.removeItem(at: store)
            }
        } catch {
            LoggerProxy.error("ZappMessaging wipe failed: \(error)")
        }

        stateSubject.send(ZappMessagingState())
        conversationsSubject.send([])
        await ChatPushNotifications.shared.clearTopics()
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
                await self.reassertPrivacySettings(sdk)
                self.mutate {
                    $0.identity = identity
                    $0.identityErrorCode = nil
                    $0.phase = .ready
                }

                do {
                    try await self.refreshConversations()
                } catch {
                    // Derivation succeeded; do not misreport it as an identity failure.
                }
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
        do {
            try await sdk.refreshConversations()
            conversationsSubject.send(await sdk.conversations)
            clearFailure(for: .local(.conversationRefresh))
            await syncPushNotifications()
        } catch {
            recordFailure(.local(.conversationRefresh), error)
            throw error
        }
    }

    func syncPushNotifications() async {
        guard let sdk else { return }
        do {
            let snapshot = try await sdk.getPushTopicSnapshot()
            await ChatPushNotifications.shared.sync(snapshot)
        } catch {
            LoggerProxy.error("Chat push topic snapshot failed: \(error.localizedDescription)")
        }
    }

    func connectionDetails() async throws -> ZMConnectionDetails {
        guard let sdk else { throw ZMError.notInitialized }
        do {
            let details = try await sdk.getConnectionDetails()
            clearFailure(for: .local(.connectionDetails))
            return details
        } catch {
            recordFailure(.local(.connectionDetails), error)
            throw error
        }
    }

    @MainActor
    func createDirectConversation(publicKey: String, displayName: String?) async throws -> ZMConversation {
        guard let sdk else { throw ZMError.notInitialized }

        let normalizedKey = PublicKeyRules.sanitize(publicKey)
        guard normalizedKey != PublicKeyRules.sanitize(sdk.identity?.publicKey ?? "") else {
            let error = ZappMessagingAppError.ownPublicKey
            recordFailure(.local(.conversationCreate), error)
            throw error
        }

        // Re-open rather than fork: the core keys a direct conversation on its
        // participant, so creating a second one for the same peer would split the
        // history in two.
        if let existing = sdk.conversations.first(where: {
            $0.type == .direct && $0.participantIds.contains {
                PublicKeyRules.sanitize($0) == normalizedKey
            }
        }) {
            do {
                try await sdk.ensureConversationConnected(existing.id)
                clearFailure(for: .local(.conversationConnect))
                return existing
            } catch {
                recordFailure(.local(.conversationConnect), error)
                throw error
            }
        }

        do {
            let conversation = try await sdk.createConversation(
                type: .direct,
                participants: [normalizedKey],
                displayName: displayName
            )
            conversationsSubject.send(sdk.conversations)
            clearFailure(for: .local(.conversationCreate))
            return conversation
        } catch {
            recordFailure(.local(.conversationCreate), error)
            throw error
        }
    }

    func messages(conversationId: String, limit: Int) async throws -> [ZMMessage] {
        guard let sdk else { throw ZMError.notInitialized }
        do {
            let messages = try await sdk.getMessages(conversationId: conversationId, limit: limit)
            clearFailure(for: .local(.messageList))
            return messages
        } catch {
            recordFailure(.local(.messageList), error)
            throw error
        }
    }

    func sendMessage(conversationId: String, content: String, replyTo: ZMReplyContext?) async throws -> ZMMessage {
        guard let sdk else { throw ZMError.notInitialized }
        let protection = await beginProtectedSend(named: "Finish chat message")
        do {
            try await validateRecipient(conversationId: conversationId, sdk: sdk)
            let message = try await sdk.sendMessage(conversationId: conversationId, content: content, replyTo: replyTo)
            publishMessageActivity(message)
            await finishProtectedSend(protection)
            clearFailure(for: .local(.messageSend))
            return message
        } catch {
            await finishProtectedSend(protection)
            recordFailure(.local(.messageSend), error)
            throw error
        }
    }

    func markRead(conversationId: String) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        do {
            try await sdk.markRead(conversationId: conversationId)
            clearUnread(for: conversationId)
            clearFailure(for: .local(.messageMarkRead))
        } catch {
            recordFailure(.local(.messageMarkRead), error)
            throw error
        }
    }

    func setBlockedKeys(_ keys: Set<String>) {
        lock.withLock { blockedKeys = keys }
    }

    func setActiveConversation(_ conversationId: String?) {
        lock.withLock { activeConversationId = conversationId }
        if let conversationId {
            clearUnread(for: conversationId)
        }
    }

    // MARK: - Groups

    @MainActor
    func createGroup(name: String, participantKeys: [String]) async throws -> ZMConversation {
        guard let sdk else { throw ZMError.notInitialized }

        let conversation = try await sdk.createConversation(
            type: .group,
            participants: participantKeys.map(PublicKeyRules.sanitize),
            displayName: name
        )
        conversationsSubject.send(sdk.conversations)

        return conversation
    }

    func renameGroup(conversationId: String, name: String) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        try await sdk.renameGroup(conversationId: conversationId, name: name)
        conversationsSubject.send(await sdk.conversations)
    }

    func addMember(conversationId: String, publicKey: String, displayName: String?) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        try await sdk.addMember(
            conversationId: conversationId,
            publicKey: PublicKeyRules.sanitize(publicKey),
            displayName: displayName
        )
        conversationsSubject.send(await sdk.conversations)
    }

    func leaveConversation(_ conversationId: String) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        try await sdk.leaveConversation(conversationId)
        conversationsSubject.send(await sdk.conversations)
        clearUnread(for: conversationId)
    }

    func removeConversation(_ conversationId: String) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        try await sdk.removeConversation(conversationId)
        conversationsSubject.send(await sdk.conversations)
        clearUnread(for: conversationId)
    }

    func hasLeftDirectConversation(publicKey: String) async throws -> Bool {
        guard let sdk else { throw ZMError.notInitialized }
        return try await sdk.hasLeftDirectConversation(publicKey: publicKey)
    }

    // MARK: - Media

    func sendMedia(
        conversationId: String,
        mediaPath: String,
        contentType: String,
        caption: String,
        thumbnailData: String?
    ) async throws -> ZMMessage {
        guard let sdk else { throw ZMError.notInitialized }
        let protection = await beginProtectedSend(named: "Finish chat media message")

        do {
            try await validateRecipient(conversationId: conversationId, sdk: sdk)
            let message = try await sdk.sendMediaMessage(
                conversationId: conversationId,
                mediaPath: mediaPath,
                contentType: contentType,
                caption: caption,
                thumbnailData: thumbnailData
            )
            publishMessageActivity(message)
            await finishProtectedSend(protection)
            clearFailure(for: .local(.mediaSend))
            return message
        } catch {
            await finishProtectedSend(protection)
            recordFailure(.local(.mediaSend), error)
            throw error
        }
    }

    // MARK: - Privacy toggles

    func setReadReceiptsEnabled(_ enabled: Bool) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        do {
            try await sdk.setReadReceiptsEnabled(enabled)
            userDefaults.setValue(enabled, PrefKey.readReceipts)
            mutate { $0.readReceiptsEnabled = enabled }
            clearFailure(for: .local(.setReadReceipts))
        } catch {
            recordFailure(.local(.setReadReceipts), error)
            throw error
        }
    }

    func setPresenceVisible(_ visible: Bool) async throws {
        guard let sdk else { throw ZMError.notInitialized }
        do {
            try await sdk.setPresenceVisible(visible)
            userDefaults.setValue(visible, PrefKey.presence)
            mutate { $0.presenceVisible = visible }
            clearFailure(for: .local(.setPresenceVisible))
        } catch {
            recordFailure(.local(.setPresenceVisible), error)
            throw error
        }
    }

    /// The worklet optimistically turns read receipts ON at identity create/restore,
    /// before it has any idea what the user actually wants. Until this runs, a user
    /// who turned receipts OFF is silently emitting them. Re-assert both the moment
    /// identity lands — this is a privacy fix, not a tidiness one.
    @MainActor
    private func reassertPrivacySettings(_ sdk: ZappMessagingSDK) async {
        let receipts = (userDefaults.objectForKey(PrefKey.readReceipts) as? Bool) ?? true
        let presence = (userDefaults.objectForKey(PrefKey.presence) as? Bool) ?? true

        do {
            try await sdk.setReadReceiptsEnabled(receipts)
        } catch {
            recordFailure(.local(.setReadReceipts), error)
        }
        do {
            try await sdk.setPresenceVisible(presence)
        } catch {
            recordFailure(.local(.setPresenceVisible), error)
        }

        mutate {
            $0.readReceiptsEnabled = receipts
            $0.presenceVisible = presence
        }
    }

    // MARK: - Event wiring

    @MainActor
    private func observe(_ sdk: ZappMessagingSDK) {
        sdk.messageReceived
            .receive(on: mainQueue)
            .sink { [weak self] _, message in
                guard let self else { return }
                self.countUnread(message)
                self.publishMessageActivity(message)
                self.messageReceivedSubject.send(message)
                Task {
                    do {
                        try await self.refreshConversations()
                    } catch {
                        // `refreshConversations` records the structured failure.
                    }
                }
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

        sdk.messageStatus
            .receive(on: mainQueue)
            .sink { [weak self] status in self?.messageStatusSubject.send(status) }
            .store(in: &cancellables)

        sdk.pushTopicsChanged
            .receive(on: mainQueue)
            .sink { [weak self] in
                Task {
                    await self?.syncPushNotifications()
                }
            }
            .store(in: &cancellables)

        sdk.operationalFailure
            .receive(on: mainQueue)
            .sink { [weak self] failure in
                self?.recordFailure(
                    .sdk(failure.operation),
                    code: .operational(failure.code),
                    message: failure.message,
                    severity: failure.operation == .pushNotification ? .advisory : .error
                )
            }
            .store(in: &cancellables)

        // Keyed by CONVERSATION, not peer: the core truncates peerId to 12 chars, so
        // it tells us that someone in this conversation is online, not who.
        sdk.peerStatus
            .receive(on: mainQueue)
            .sink { [weak self] conversationId, _, status in
                self?.mutate {
                    if status == "online" {
                        $0.onlineConversationIds.insert(conversationId)
                    } else {
                        $0.onlineConversationIds.remove(conversationId)
                    }
                }
            }
            .store(in: &cancellables)

        sdk.mediaTransferProgress
            .receive(on: mainQueue)
            .sink { [weak self] progress in self?.mediaProgressSubject.send(progress) }
            .store(in: &cancellables)

        // Incoming media needs this as much as outgoing does: a GIF travels
        // uncompressed, so without download progress the bubble sits on a blurred
        // 64px thumbnail for the whole transfer and reads as broken rather than loading.
        sdk.mediaDownloadProgress
            .receive(on: mainQueue)
            .sink { [weak self] progress in self?.mediaProgressSubject.send(progress) }
            .store(in: &cancellables)

        sdk.mediaDownloadComplete
            .receive(on: mainQueue)
            .sink { [weak self] complete in self?.mediaCompleteSubject.send(complete) }
            .store(in: &cancellables)
    }

    /// Unread is counted app-side, not read off the wire — the core never sends
    /// an `unreadCount` and `ZMConversation` never carries one.
    private func countUnread(_ message: ZMMessage) {
        guard !message.isFromMe else { return }
        guard !lock.withLock({ blockedKeys }).contains(PublicKeyRules.sanitize(message.senderId)) else { return }
        guard lock.withLock({ activeConversationId }) != message.conversationId else { return }

        let counts: [String: Int] = lock.withLock {
            unreadCounts[message.conversationId, default: 0] += 1
            return unreadCounts
        }
        publishUnread(counts)
    }

    /// Keep the list responsive to message activity without waiting for the core's
    /// follow-up conversation refresh. The later refresh remains authoritative, but
    /// this snapshot ensures a newly queued or received message moves its chat to the
    /// top immediately.
    private func publishMessageActivity(_ message: ZMMessage) {
        var conversations = conversationsSubject.value

        guard let index = conversations.firstIndex(where: { $0.id == message.conversationId }) else {
            return
        }

        let previousTimestamp = conversations[index].lastMessageTimestamp ?? .distantPast
        guard message.timestamp >= previousTimestamp else { return }

        conversations[index].lastMessage = Self.preview(for: message)
        conversations[index].lastMessageTimestamp = message.timestamp
        conversationsSubject.send(conversations)
    }

    /// The same sentinels the JS core writes on a cold load, so an optimistic row and a
    /// reloaded one read identically. Mirrors `lastMessagePreview` on Android.
    private static func preview(for message: ZMMessage) -> String {
        if !message.content.isEmpty {
            return message.content
        }

        switch message.contentType {
        case "image/gif": return "[GIF]"
        case let type where type.hasPrefix("image/"): return "[Photo]"
        case let type where type.hasPrefix("video/"): return "[Video]"
        default: return message.mediaId == nil ? message.content : "[File]"
        }
    }

    private func clearUnread(for conversationId: String) {
        let counts: [String: Int] = lock.withLock {
            unreadCounts[conversationId] = nil
            return unreadCounts
        }
        publishUnread(counts)
    }

    private func publishUnread(_ counts: [String: Int]) {
        mutate {
            $0.unreadCounts = counts
            $0.totalUnreadCount = counts.values.reduce(0, +)
        }
    }

    // MARK: - Helpers

    private func mutate(_ change: (inout ZappMessagingState) -> Void) {
        var state = stateSubject.value
        change(&state)
        guard state != stateSubject.value else { return }
        stateSubject.send(state)
    }

    @MainActor
    private func validateRecipient(conversationId: String, sdk: ZappMessagingSDK) throws {
        guard let conversation = sdk.conversations.first(where: { $0.id == conversationId }),
              conversation.type == .direct,
              let ownKey = sdk.identity?.publicKey
        else { return }

        let normalizedOwnKey = PublicKeyRules.sanitize(ownKey)
        let hasRemoteParticipant = conversation.participantIds.contains {
            PublicKeyRules.sanitize($0) != normalizedOwnKey
        }
        guard hasRemoteParticipant else { throw ZappMessagingAppError.ownPublicKey }
    }

    private func recordFailure(_ operation: ZappMessagingOperation, _ error: Error) {
        let nsError = error as NSError
        recordFailure(operation, code: ZappMessagingFailureCode(error: error), message: nsError.localizedDescription)
    }

    private func recordFailure(
        _ operation: ZappMessagingOperation,
        code: ZappMessagingFailureCode,
        message: String,
        severity: ZappMessagingFailure.Severity = .error
    ) {
        mutate {
            if $0.lastFailure?.severity == .error && severity == .advisory { return }
            $0.lastFailure = ZappMessagingFailure(
                operation: operation,
                code: code,
                message: message,
                severity: severity,
                occurredAt: Date()
            )
        }
        LoggerProxy.error("ZappMessaging \(operation.identifier) failed [\(code.identifier)]: \(message)")
    }

    private func clearFailure(for operation: ZappMessagingOperation) {
        mutate {
            if let failedOperation = $0.lastFailure?.operation,
               operation.recovers(failedOperation) {
                $0.lastFailure = nil
            }
        }
    }

    /// Stable codes for the setup screen's error line, mirroring Android's
    /// SetupErrorCode. Never contains the seed, the key or the name.
    private static func errorCode(_ error: Error) -> String {
        ZappMessagingFailureCode(error: error).identifier
    }

    private func requestLifecycleState(_ state: MessagingLifecycleOwner.State) {
        let sequence = lock.withLock {
            lifecycleRequestSequence &+= 1
            return lifecycleRequestSequence
        }
        Task { await lifecycle.setApplicationState(state, sequence: sequence) }
    }

    private func beginProtectedSend(named name: String) async -> (UUID, MessagingBackgroundTask) {
        let sendID = await lifecycle.beginSend()
        let task = await MainActor.run {
            MessagingBackgroundTask(name: name) { [weak self] in
                LoggerProxy.warn("ZappMessaging: bounded send flush expired")
                Task { await self?.lifecycle.backgroundTimeExpired() }
            }
        }
        return (sendID, task)
    }

    private func finishProtectedSend(_ protection: (UUID, MessagingBackgroundTask)) async {
        await lifecycle.finishSend(protection.0)
        await protection.1.end()
    }
}

@MainActor
private final class MessagingBackgroundTask: @unchecked Sendable {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private let expiration: @MainActor () -> Void

    init(name: String, expiration: @escaping @MainActor () -> Void) {
        self.expiration = expiration
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            guard let self else { return }
            self.expiration()
            self.end()
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
