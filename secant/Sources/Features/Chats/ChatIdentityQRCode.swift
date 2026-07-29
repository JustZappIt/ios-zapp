//
//  ChatIdentityQRCode.swift
//  Zapp
//
//  Your messaging public key as a QR code. Shared by the profile screen and the
//  new-chat share sheet so the code someone scans is rendered one way only.
//

import SwiftUI
import UIKit

struct ChatIdentityQRCode: View {
    private enum Constants {
        static let defaultSize: CGFloat = 176
    }

    let publicKey: String
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
        .task(id: publicKey) {
            guard !publicKey.isEmpty else {
                image = nil
                return
            }

            image = await QRCodeGenerator.generate(
                from: publicKey,
                maxPrivacy: false,
                color: .black,
                overlayedWithZcashLogo: false
            )
        }
    }
}

#Preview {
    ChatIdentityQRCode(publicKey: String(repeating: "a", count: PublicKeyRules.hexLength))
}
