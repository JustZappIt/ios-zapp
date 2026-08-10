//
//  SendCoordFlowView.swift
//  Zashi
//
//  Created by Lukáš Korba on 2023-03-18.
//

import SwiftUI
import ComposableArchitecture

struct SendCoordFlowView: View {
    @Environment(\.colorScheme) var colorScheme

    @Perception.Bindable var store: StoreOf<SendCoordFlow>
    let tokenName: String

    init(store: StoreOf<SendCoordFlow>, tokenName: String) {
        self.store = store
        self.tokenName = tokenName
    }

    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                ZappUnifiedSendView(store: store, tokenName: tokenName)
            } destination: { store in
                switch store.case {
                case let .addressBook(store):
                    AddressBookView(store: store)
                case let .addressBookContact(store):
                    AddressBookContactView(store: store)
                case let .confirmWithKeystone(store):
                    SignWithKeystoneView(store: store, tokenName: tokenName)
                case let .keystoneFirmwareUpdate(store):
                    KeystoneFirmwareUpdateView(store: store)
                case let .preSendingFailure(store):
                    PreSendingFailureView(store: store, tokenName: tokenName)
                case let .scan(store):
                    ScanView(store: store)
                case let .sendConfirmation(store):
                    SendConfirmationView(store: store, tokenName: tokenName)
                case let .sending(store):
                    SendingView(store: store, tokenName: tokenName)
                case let .requestZecConfirmation(store):
                    RequestPaymentConfirmationView(store: store, tokenName: tokenName)
                case let .sendResultFailure(store):
                    FailureView(store: store, tokenName: tokenName)
                case let .sendResultPending(store):
                    PendingView(store: store, tokenName: tokenName)
                case let .sendResultSuccess(store):
                    SuccessView(store: store, tokenName: tokenName)
                case let .transactionDetails(store):
                    TransactionDetailsView(store: store, tokenName: tokenName)
                }
            }
            .navigationBarHidden(true)
        }
        .background(ZappColors.bg.color(colorScheme))
    }
}

#Preview {
    NavigationView {
        SendCoordFlowView(store: SendCoordFlow.placeholder, tokenName: "ZEC")
    }
}

// MARK: - Placeholders

extension SendCoordFlow.State {
    static var initial: SendCoordFlow.State { SendCoordFlow.State() }
}

extension SendCoordFlow {
    @MainActor static let placeholder = StoreOf<SendCoordFlow>(
        initialState: .initial
    ) {
        SendCoordFlow()
    }
}
