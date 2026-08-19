//
//  ChatWalletAddressStore.swift
//  Zapp
//
//  Every address someone could pay you, on one screen — Android's `ChatWalletAddressVM`.
//

import ComposableArchitecture
import Foundation

@Reducer
struct ChatWalletAddress {
    /// The order Android lists them in.
    enum AddressKind: Hashable, CaseIterable {
        case shielded
        case transparent
        case base
    }

    struct AddressItem: Equatable, Identifiable {
        let kind: AddressKind
        let address: String

        var id: AddressKind { kind }

        /// Base settles on an EVM chain, and Android offers no code for it — those wallets are
        /// pasted into, not scanned.
        var hasQRCode: Bool { kind != .base }

        var label: String {
            switch kind {
            case .shielded: return String(localizable: .chatProfileAddressShieldedLabel)
            case .transparent: return String(localizable: .chatProfileAddressTransparentLabel)
            case .base: return String(localizable: .chatProfileAddressBaseLabel)
            }
        }

        var caption: String {
            switch kind {
            case .shielded: return String(localizable: .chatProfileAddressShieldedCaption)
            case .transparent: return String(localizable: .chatProfileAddressTransparentCaption)
            case .base: return String(localizable: .chatProfileAddressBaseCaption)
            }
        }
    }

    @ObservableState
    struct State: Equatable {
        /// The SELECTED account, as Android's `observeSelectedWalletAccount` does — not the Zashi
        /// one. `offramp.accountAddress()` resolves against the selection too, so reading anything
        /// else here would hand out a Keystone user the software wallet's addresses.
        @Shared(.inMemory(.selectedWalletAccount)) var selectedWalletAccount: WalletAccount?

        /// Nil both before the lookup finishes and after it fails — the card is simply absent.
        var baseAddress: String?

        /// One field rather than a flag per card, so copying a second address moves the tick
        /// instead of lighting two at once.
        var copiedAddress: String?

        var addresses: [AddressItem] {
            [
                (AddressKind.shielded, selectedWalletAccount?.unifiedAddress),
                (AddressKind.transparent, selectedWalletAccount?.transparentAddress),
                (AddressKind.base, baseAddress)
            ].compactMap { kind, address in
                guard let address, !address.isEmpty else { return nil }

                return AddressItem(kind: kind, address: address)
            }
        }

        init() { }
    }

    enum Action: Equatable {
        case onAppear
        case onDisappear
        case baseAddressLoaded(String?)
        case copyAddressTapped(String)
        case copyIndicatorExpired
        /// Consumed by Root, which returns to Profile & identity rather than the You tab.
        case backTapped
    }

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.offramp) var offramp
    @Dependency(\.pasteboard) var pasteboard

    init() { }

    enum CancelID {
        case baseAddress
        case copyIndicator
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
                // Best effort: the two local Zcash addresses do not wait on this network round
                // trip, and a failure drops the Base card rather than the screen.
            case .onAppear:
                return .run { send in
                    do {
                        await send(.baseAddressLoaded(try await offramp.accountAddress()))
                    } catch {
                        // Deliberately not interpolating `error`: it can echo back the account
                        // it was resolving.
                        LoggerProxy.warn("ChatWalletAddress: Base account address unavailable")
                        await send(.baseAddressLoaded(nil))
                    }
                }
                .cancellable(id: CancelID.baseAddress, cancelInFlight: true)

            case .onDisappear:
                return .merge(
                    .cancel(id: CancelID.baseAddress),
                    .cancel(id: CancelID.copyIndicator)
                )

            case .baseAddressLoaded(let address):
                state.baseAddress = (address?.isEmpty ?? true) ? nil : address
                return .none

            case .copyAddressTapped(let address):
                guard !address.isEmpty else { return .none }

                pasteboard.setString(RedactableString(address))
                state.copiedAddress = address

                return .run { send in
                    try await mainQueue.sleep(for: .seconds(2))
                    await send(.copyIndicatorExpired)
                }
                .cancellable(id: CancelID.copyIndicator, cancelInFlight: true)

            case .copyIndicatorExpired:
                state.copiedAddress = nil
                return .none

            case .backTapped:
                return .none
            }
        }
    }
}

// MARK: Placeholders

extension ChatWalletAddress.State {
    static var initial: ChatWalletAddress.State {
        .init()
    }
}

extension ChatWalletAddress {
    @MainActor
    static let initial = StoreOf<ChatWalletAddress>(
        initialState: .initial
    ) {
        ChatWalletAddress()
    }
}
