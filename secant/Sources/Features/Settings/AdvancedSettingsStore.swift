import SwiftUI
import ComposableArchitecture
import MessageUI

@Reducer
struct AdvancedSettings {
    @ObservableState
    struct State: Equatable {
        enum Operation: Equatable {
            case chooseServer
            case disconnectHWWallet
            case exportPrivateData
            case exportTaxFile
            case recoveryPhrase
            case resetZashi
            case resyncWallet
            case torSetup
        }
        
        var isEnoughFreeSpaceMode = true
        @Shared(.inMemory(.walletAccounts)) var walletAccounts: [WalletAccount] = []

        var isKeystoneConnected: Bool {
            for account in walletAccounts {
                if account.vendor == .keystone {
                    return true
                }
            }
            
            return false
        }

        init() { }
    }

    enum Action: Equatable {
        case debugResetIronwoodAnnouncementTapped
        case operationAccessCheck(State.Operation)
        case operationAccessGranted(State.Operation)
    }

    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.walletStorage) var walletStorage

    init() { }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .debugResetIronwoodAnnouncementTapped:
                // Root observes the same action to clear its session latch.
                // No biometric gate is needed because this destroys nothing.
                try? walletStorage.importIronwoodAnnouncementFlag(false)
                return .none

            case .operationAccessCheck(let operation):
                switch operation {
                case .chooseServer, .torSetup:
                    return .send(.operationAccessGranted(operation))
                case .recoveryPhrase, .exportPrivateData, .exportTaxFile, .resetZashi, .disconnectHWWallet, .resyncWallet:
                    return .run { send in
                        if await localAuthentication.authenticate() {
                            await send(.operationAccessGranted(operation))
                        }
                    }
                }
                
            case .operationAccessGranted:
                return .none
            }
        }
    }
}
