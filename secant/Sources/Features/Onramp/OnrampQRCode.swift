// SPDX-License-Identifier: MIT OR Apache-2.0

import SwiftUI

struct OnrampQRCode: View {
    let payload: String
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: UIImage(cgImage: image))
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                Asset.Colors.ZDesign.Base.bone.color
            }
        }
        .task(id: payload) {
            image = await QRCodeGenerator.generate(
                from: payload,
                maxPrivacy: false,
                color: Asset.Colors.ZDesign.Base.black.systemColor,
                overlayedWithZcashLogo: false
            )
        }
    }
}
