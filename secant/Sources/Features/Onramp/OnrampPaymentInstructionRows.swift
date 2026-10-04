//
//  OnrampPaymentInstructionRows.swift
//  Zapp
//

import SwiftUI

/// Where to send the money, mirroring Android's `InstructionRows` (`OnrampPaymentSection.kt:101-120`):
/// one "Pay to" row for a UPI or plain handle, one labelled row per field for a direct corridor
/// (PIX key, account number, Cédula, …), and nothing for a bare QR, which the code below the card
/// already carries.
struct OnrampPaymentInstructionRows: View {
    private enum Constants {
        static let copyIconSize: CGFloat = 20
        static let copyTarget: CGFloat = 36
    }

    let instruction: OnrampPaymentInstructionModel
    let onCopyField: (Int) -> Void

    var body: some View {
        switch instruction {
        case .upi(let address, _), .plain(let address):
            ZappSummaryRow(label: String(localizable: .onrampPaymentAddressLabel), value: address)
        case .fields(let fields, _):
            ForEach(Array(fields.enumerated()), id: \.offset) { index, field in
                fieldRow(field, index: index)
            }
        case .qr:
            EmptyView()
        }
    }

    /// A bank transfer is typed into the bank's own app one field at a time, so each value gets its
    /// own copy button beside the card-wide "Copy payment details".
    private func fieldRow(_ field: OnrampFieldModel, index: Int) -> some View {
        let label = Self.label(for: field)
        return HStack(spacing: 4) {
            ZappSummaryRow(label: label, value: field.value)
            Button { onCopyField(index) } label: {
                Asset.Assets.copy.image
                    .zImage(width: Constants.copyIconSize, height: Constants.copyIconSize, style: ZappColors.textMuted)
                    .frame(width: Constants.copyTarget, height: Constants.copyTarget)
            }
            .buttonStyle(.zappPress)
            .accessibilityLabel(String(localizable: .onrampCopyAddress))
            .accessibilityValue(label)
        }
    }

    /// Android's `Field.label()`: a provider's own label as sent, a known kind in the user's
    /// language, and "Pay to" when the bridge sent no label at all.
    static func label(for field: OnrampFieldModel) -> String {
        if let kind = field.kind { return label(for: kind) }
        return field.label.isEmpty ? String(localizable: .onrampPaymentAddressLabel) : field.label
    }

    static func label(for kind: OnrampPaymentFieldKind) -> String {
        switch kind {
        case .phoneNumber: return String(localizable: .onrampPaymentFieldPhoneNumber)
        case .documentID: return String(localizable: .onrampPaymentFieldDocumentID)
        case .bank: return String(localizable: .onrampPaymentFieldBank)
        case .accountNumber: return String(localizable: .onrampPaymentFieldAccountNumber)
        case .bankName: return String(localizable: .onrampPaymentFieldBankName)
        case .accountName: return String(localizable: .onrampPaymentFieldAccountName)
        case .cardNumber: return String(localizable: .onrampPaymentFieldCardNumber)
        case .accountType: return String(localizable: .onrampPaymentFieldAccountType)
        case .cedula: return String(localizable: .onrampPaymentFieldCedula)
        case .cci: return String(localizable: .onrampPaymentFieldCci)
        case .pixKey: return String(localizable: .onrampPaymentFieldPixKey)
        case .paymentAlias: return String(localizable: .onrampPaymentFieldAlias)
        }
    }
}
