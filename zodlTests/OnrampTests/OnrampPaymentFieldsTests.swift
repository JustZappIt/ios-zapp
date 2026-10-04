// SPDX-License-Identifier: MIT OR Apache-2.0

import ComposableArchitecture
import Foundation
import Testing
@testable import zodl_internal
@preconcurrency import ZappOfframp

/// Direct-corridor payment fields, mirroring Android's `OnrampPaymentInstruction.Fields` and the
/// Apple bridge that carries it (`AppleOnrampClient.toApple`: `label ?: kind?.name`, payload = QR).
@Suite(.serialized) @MainActor
struct OnrampPaymentFieldsTests {
    // MARK: - Decode

    /// Venezuela's Pago Móvil, as `DirectOnrampCorridorTest` expects it from the official client:
    /// a QR plus phone, document and bank.
    @Test func aDirectCorridorDecodesItsFieldsAndKeepsItsQR() throws {
        let status = try OnrampStatusModel(appleStatus(
            fields: [("PHONE_NUMBER", "04121234567"), ("DOCUMENT_ID", "V12345678"), ("BANK", "Banesco")],
            payload: "QUJDRA==?merchantId=123"
        ))

        guard case .fields(let fields, let qrPayload) = status.instruction else {
            Issue.record("expected a fields instruction, got \(String(describing: status.instruction))")
            return
        }
        #expect(fields.map(\.kind) == [.phoneNumber, .documentID, .bank])
        #expect(fields.map(\.value) == ["04121234567", "V12345678", "Banesco"])
        #expect(qrPayload == "QUJDRA==?merchantId=123")
        // The amount guard reads the same QR Android's `OnrampIntentAmount` does.
        #expect(status.instruction?.payload == "QUJDRA==?merchantId=123")
    }

    @Test func fieldsWithoutAQRDecodeWithNoPayload() throws {
        let status = try OnrampStatusModel(appleStatus(fields: [("PIX_KEY", "alice@example.com")], payload: nil))

        #expect(status.instruction == .fields([OnrampFieldModel(label: "PIX_KEY", value: "alice@example.com")], qrPayload: nil))
        #expect(status.instruction?.payload == "")
    }

    /// Anything this build cannot name still reaches the user: an unknown kind or a provider's own
    /// label shows as sent, a missing label falls back to "Pay to", and blanks are dropped.
    @Test func unknownAndMissingFieldsFallBackInsteadOfDisappearing() throws {
        let status = try OnrampStatusModel(appleStatus(
            fields: [("SWIFT_CODE", "BNVZVECA"), ("", "merchant-handle"), ("ACCOUNT_NAME", "   ")],
            payload: "  "
        ))

        guard case .fields(let fields, let qrPayload) = status.instruction else {
            Issue.record("expected a fields instruction")
            return
        }
        #expect(fields.count == 2)
        #expect(fields.map(\.kind) == [nil, nil])
        #expect(OnrampPaymentInstructionRows.label(for: fields[0]) == "SWIFT_CODE")
        #expect(OnrampPaymentInstructionRows.label(for: fields[1]) == String(localizable: .onrampPaymentAddressLabel))
        #expect(qrPayload == nil)
    }

    @Test func everyKindHasItsOwnLocalizedLabel() {
        let labels = OnrampPaymentFieldKind.allCases.map(OnrampPaymentInstructionRows.label(for:))
        #expect(Set(labels).count == OnrampPaymentFieldKind.allCases.count)
        #expect(OnrampPaymentInstructionRows.label(for: OnrampFieldModel(label: "PIX_KEY", value: "x")) == String(localizable: .onrampPaymentFieldPixKey))
        #expect(OnrampPaymentInstructionRows.label(for: OnrampFieldModel(label: "CEDULA", value: "x")) == String(localizable: .onrampPaymentFieldCedula))
    }

    // MARK: - Store

    @Test func fieldsFeedTheQRAndCopyAndroidsValue() {
        var state = Onramp.State.initial(currencyCode: "VEN")
        state.paymentInstruction = .fields(venezuelanFields, qrPayload: "QUJDRA==?merchantId=123")

        #expect(state.qrPayload == "QUJDRA==?merchantId=123")
        // Android's `Fields.copyValue`: the bare values joined by "|", no labels.
        #expect(state.paymentAddress == "04121234567|V12345678|Banesco")
    }

    @Test func eachFieldCopiesOnlyItsOwnValue() async {
        let copied = LockIsolated<[String]>([])
        var state = Onramp.State.initial(currencyCode: "VEN")
        state.paymentInstruction = .fields(venezuelanFields, qrPayload: nil)
        let store = TestStore(initialState: state) { Onramp() } withDependencies: {
            $0.pasteboard.setString = { value in copied.withValue { $0.append(value.data) } }
        }

        await store.send(.copyPaymentFieldTapped(1))
        await store.send(.copyPaymentFieldTapped(7)) // out of range: nothing copied
        await store.send(.copyPaymentAddressTapped)

        #expect(copied.value == ["V12345678", "04121234567|V12345678|Banesco"])
    }

    // MARK: - Helpers

    private var venezuelanFields: [OnrampFieldModel] {
        [
            OnrampFieldModel(label: "PHONE_NUMBER", value: "04121234567"),
            OnrampFieldModel(label: "DOCUMENT_ID", value: "V12345678"),
            OnrampFieldModel(label: "BANK", value: "Banesco")
        ]
    }

    private func appleStatus(fields: [(String, String)], payload: String?) -> AppleOnrampStatus {
        AppleOnrampStatus(
            kind: "awaitingPayment",
            phase: "AWAITING_PAYMENT",
            id: "743",
            orderId: "743",
            failureCode: nil,
            failureDetail: nil,
            instructionKind: "fields",
            instructionAddress: nil,
            instructionPayload: payload,
            instructionFields: fields.map { AppleOnrampField(label: $0.0, value: $0.1) },
            fiatMicros: "100000000",
            netUsdcMicros: nil,
            recipientAddress: nil,
            paidTx: nil,
            expiresAtMillis: nil,
            isTerminal: false
        )
    }
}
