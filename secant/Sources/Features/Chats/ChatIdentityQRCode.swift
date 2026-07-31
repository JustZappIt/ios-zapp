//
//  ChatIdentityQRCode.swift
//  Zapp
//
//  A chat identity as a QR code — a messaging public key, or the wallet address the
//  profile screen shows beside it. Shared by the profile screen and the new-chat share
//  sheet so the code someone scans is rendered one way only.
//

import SwiftUI
import UIKit

struct ChatIdentityQRCode: View {
    private enum Constants {
        static let defaultSize: CGFloat = 176
    }

    let payload: String
    var size: CGFloat = Constants.defaultSize

    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Rectangle()
                    .fill(Color.white)
            }
        }
        .frame(width: size, height: size)
        .background(Color.white)
        .task(id: payload) {
            guard !payload.isEmpty else {
                image = nil
                return
            }

            image = await QRCodeGenerator.generate(
                from: payload,
                maxPrivacy: false,
                color: .black,
                overlayedWithZcashLogo: false
            )
        }
    }
}

#Preview {
    ChatIdentityQRCode(payload: String(repeating: "a", count: PublicKeyRules.hexLength))
}
