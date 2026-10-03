//
//  ZappOnboardingLoadingView.swift
//  Zapp
//
//  The accent "Hey." loading screen shared by wallet creation, restore and identity derivation,
//  Android's `WalletEncryptingScreen`. Lifted out of `RestoreWalletCoordFlowView` once the restore
//  steps, which live in their own files, needed it.
//

import SwiftUI

struct ZappOnboardingLoadingView: View {
    private enum Constants {
        /// Android's `ENCRYPT_TIMEOUT_MS`: a fallback so the user is never left on an endless
        /// animation when nothing errors but the work never finishes either.
        static let timeout: Duration = .seconds(15)
    }

    @Environment(\.colorScheme) private var colorScheme

    @State private var pulse = false
    @State private var hasTimedOut = false

    let message: String
    let errorMessage: String?
    var errorDetail: String?
    var retryHint = String(localizable: .onboardingLoadingRetryHint)
    var noRetryHint = String(localizable: .onboardingLoadingNoRetryHint)
    let onRetry: (() -> Void)?

    private var displayedError: String? {
        errorMessage ?? (hasTimedOut ? String(localizable: .onboardingLoadingTimeout) : nil)
    }

    var body: some View {
        ZStack {
            ZappLoadingWave(heightFraction: pulse ? 0.48 : 0.30)
                .fill(Color.white.opacity(0.10))
            ZappLoadingWave(heightFraction: pulse ? 0.20 : 0.36)
                .fill(Color.white.opacity(0.16))

            VStack(spacing: 0) {
                Text(localizable: .onboardingLoadingGreeting)
                    .zappFont(.onboardingGreeting, color: .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)

                Rectangle()
                    .fill(ZappColors.text.color(colorScheme))
                    .frame(width: 36, height: 3)
                    .padding(.top, 20)

                if let displayedError {
                    errorContent(displayedError)
                } else {
                    Text(message)
                        .zappFont(.rowTitle, color: .white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 24)

                    TimelineView(.periodic(from: .now, by: 0.4)) { context in
                        let active = Int(context.date.timeIntervalSinceReferenceDate / 0.4) % 3
                        HStack(spacing: 10) {
                            ForEach(0..<3, id: \.self) { index in
                                Rectangle()
                                    .fill(
                                        ZappColors.text.color(colorScheme)
                                            .opacity(index == active ? 1 : 0.28)
                                    )
                                    .frame(width: 10, height: 10)
                            }
                        }
                    }
                    .frame(height: 10)
                    .padding(.top, 28)
                }
            }
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ZappColors.accent.color(colorScheme))
        .ignoresSafeArea()
        .navigationBarBackButtonHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        // Restarts whenever the error clears (a retry), as Android's `LaunchedEffect(errorMessage)`.
        .task(id: errorMessage == nil) {
            hasTimedOut = false
            guard errorMessage == nil else { return }
            try? await Task.sleep(for: Constants.timeout)
            if !Task.isCancelled {
                hasTimedOut = true
            }
        }
    }

    @ViewBuilder private func errorContent(_ error: String) -> some View {
        Text(error)
            .zappFont(.rowTitle, style: ZappColors.text)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 24)

        Text(onRetry == nil ? noRetryHint : retryHint)
            .zappFont(.caption, style: ZappColors.text)
            .opacity(0.7)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)

        if let errorDetail, errorMessage != nil {
            Text(errorDetail)
                .zappFont(.mono, style: ZappColors.text)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, 10)
        }

        if let onRetry {
            Button(action: onRetry) {
                Text(localizable: .onboardingLoadingRetry)
                    .zappFont(.buttonSmall, style: ZappColors.text)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .overlay {
                        Rectangle()
                            .strokeBorder(ZappColors.text.color(colorScheme), lineWidth: 2)
                    }
            }
            .buttonStyle(.zappPress)
            .padding(.top, 22)
        }
    }
}

private extension ZappTextStyle {
    static let onboardingGreeting = ZappTextStyle(weight: .black, size: 112, lineHeight: 104, tracking: -5)
}

private struct ZappLoadingWave: Shape {
    var heightFraction: CGFloat

    var animatableData: CGFloat {
        get { heightFraction }
        set { heightFraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0.00, 0.18), (0.08, 0.56), (0.17, 0.32), (0.25, 0.78),
            (0.34, 0.45), (0.43, 0.88), (0.53, 0.38), (0.62, 0.68),
            (0.72, 0.30), (0.82, 0.82), (0.91, 0.48), (1.00, 0.66)
        ]
        let bandHeight = rect.height * heightFraction
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for point in points {
            path.addLine(
                to: CGPoint(
                    x: rect.minX + rect.width * point.0,
                    y: rect.maxY - bandHeight * point.1
                )
            )
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
