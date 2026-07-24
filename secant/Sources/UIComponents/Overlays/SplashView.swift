//
//  SplashView.swift
//
//
//  Created by Lukáš Korba on 27.09.2023.
//

import SwiftUI
import ComposableArchitecture

@MainActor
final class SplashManager: ObservableObject {
    enum LockScreen: Equatable {
        case biometricRetry
        case migrateConfirmPIN
        case migrateCreatePIN
        case none
        case verifyPIN
    }

    struct SplashShape: Shape {
        var points: [CGPoint]
        
        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: rect.width, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 0))
                points.forEach { path.addLine(to: $0) }
                path.closeSubpath()
            }
        }
    }

    @Published var points: [CGPoint] = []
    @Shared(.inMemory(.featureFlags)) var featureFlags: FeatureFlags = .initial

    let isHidden: Bool
    let screenSize: CGSize
    var task: Task<(), Never>?
    var currentMaxHeight: CGFloat = 0.0
    var step: CGFloat = 0.0
    @Published var errorMessage: String?
    @Published var isOn = true
    @Published var isProcessing = false
    @Published var lockScreen = LockScreen.none
    @Published var lockoutSeconds = 0
    @Published var pin = ""
    var firstPIN = ""
    let completion: () -> Void
    var timer: Timer?

    init(_ isHidden: Bool, completion: @escaping () -> Void) {
        self.isHidden = isHidden
        self.screenSize = UIScreen.main.bounds.size
        self.completion = completion
        
        if !isHidden {
            preparePoints()
            if featureFlags.appLaunchBiometric {
                beginAuthentication()
            } else {
                Task {
                    self.spinTheWheel()
                }
            }
        }
    }

    func beginAuthentication() {
        @Dependency(\.appSecurity) var appSecurity
        @Dependency(\.localAuthentication) var localAuthentication

        switch appSecurity.authenticationMethod() {
        case .none:
            spinTheWheel()
        case .pin:
            lockScreen = .verifyPIN
            refreshLockout()
        case .biometric:
            if localAuthentication.method() == .none {
                lockScreen = .migrateCreatePIN
            } else {
                authenticate()
            }
        }
    }

    func authenticate() {
        @Dependency(\.localAuthentication) var localAuthentication

        errorMessage = nil
        lockScreen = .none

        Task {
            if await !localAuthentication.authenticateAppLock() {
                self.authenticationFailed()
            } else {
                self.spinTheWheel()
            }
        }
    }
    
    @MainActor func authenticationFailed() {
        lockScreen = .biometricRetry
    }
}

extension SplashManager {
    func pinKeyTapped(_ key: PINKey) {
        guard !isProcessing, lockoutSeconds == 0 else {
            return
        }
        errorMessage = nil
        PINInput.apply(key, to: &pin)

        switch lockScreen {
        case .verifyPIN:
            guard PINInput.isComplete(pin) else {
                return
            }
            verifyPIN()
        case .migrateCreatePIN, .migrateConfirmPIN:
            let submission = PINInput.submit(pin: pin, firstPIN: firstPIN)
            pin = submission.pin
            firstPIN = submission.firstPIN
            switch submission.result {
            case .incomplete:
                break
            case .confirmationRequired:
                lockScreen = .migrateConfirmPIN
            case .mismatch:
                errorMessage = String(localizable: .onboardingPINMismatch)
                lockScreen = .migrateCreatePIN
            case .confirmed:
                configureMigrationPIN()
            }
        default:
            break
        }
    }

    private func verifyPIN() {
        @Dependency(\.appSecurity) var appSecurity
        @Dependency(\.date) var date

        let submittedPIN = pin
        pin = ""
        isProcessing = true
        task = Task {
            let result = await appSecurity.verifyPIN(submittedPIN, date.now())
            isProcessing = false

            switch result {
            case .success:
                lockScreen = .none
                spinTheWheel()
            case .incorrect:
                errorMessage = String(localizable: .appLockPINIncorrect)
            case let .locked(secondsRemaining):
                lockoutSeconds = secondsRemaining
                errorMessage = String(localizable: .appLockPINLocked(String(secondsRemaining)))
                startLockoutTimer()
            }
        }
    }

    private func configureMigrationPIN() {
        @Dependency(\.appSecurity) var appSecurity

        let submittedPIN = pin
        isProcessing = true
        task = Task {
            let succeeded: Bool
            do {
                try await appSecurity.configurePIN(submittedPIN)
                succeeded = true
            } catch {
                succeeded = false
            }

            isProcessing = false
            if succeeded {
                pin = ""
                firstPIN = ""
                lockScreen = .none
                spinTheWheel()
            } else {
                errorMessage = String(localizable: .appLockStorageError)
                pin = ""
                firstPIN = ""
                lockScreen = .migrateCreatePIN
            }
        }
    }

    private func refreshLockout() {
        @Dependency(\.appSecurity) var appSecurity
        @Dependency(\.date) var date

        lockoutSeconds = appSecurity.lockoutRemaining(date.now())
        if lockoutSeconds > 0 {
            errorMessage = String(localizable: .appLockPINLocked(String(lockoutSeconds)))
            startLockoutTimer()
        }
    }

    private func startLockoutTimer() {
        @Dependency(\.appSecurity) var appSecurity
        @Dependency(\.continuousClock) var continuousClock
        @Dependency(\.date) var date

        task?.cancel()
        task = Task {
            while !Task.isCancelled {
                try? await continuousClock.sleep(for: .seconds(1))
                lockoutSeconds = appSecurity.lockoutRemaining(date.now())
                if lockoutSeconds == 0 {
                    errorMessage = nil
                    break
                }
                errorMessage = String(localizable: .appLockPINLocked(String(lockoutSeconds)))
            }
        }
    }
}

extension SplashManager {
    @MainActor func spinTheWheel() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { timer in
            // Timer was scheduled from @MainActor spinTheWheel(); fires on main run loop.
            if MainActor.assumeIsolated({ self.isOn }) {
                Task { @MainActor in
                    self.tick()

                    if self.currentMaxHeight <= 0.0 {
                        self.finished()
                    }
                }
            }
        }
    }
    
    func preparePoints() {
        let pointsInControl = Int.random(in: 4...7)
        let allPoints = pointsInControl + 1
        let rangeSize = screenSize.width / CGFloat(allPoints)
        let xOffsetHelper = screenSize.width * 0.05
        
        var prevHeight = 0.0
        
        for i in stride(from: allPoints, through: 0, by: -1) {
            // x
            var randomXOffset: CGFloat = 0.0
            
            if i > 0 && i < allPoints {
                randomXOffset = CGFloat.random(in: -xOffsetHelper...xOffsetHelper)
            }
            
            let x = rangeSize * CGFloat(i) + randomXOffset
            
            // y
            let y = screenSize.height + prevHeight
            
            if (allPoints - i) % 2 == 0 {
                prevHeight += CGFloat.random(in: 30...70)
            }

            points.append(CGPoint(x: x, y: y))
        }
        
        points.reverse()
        
        var maxHeight: CGFloat = 0.0
        
        points.forEach {
            if $0.y > maxHeight {
                maxHeight = $0.y
            }
        }
        
        currentMaxHeight = maxHeight
        step = currentMaxHeight / 100.0
    }
    
    @MainActor func tick() {
        step *= 1.04
        
        var newMaxHeight: CGFloat = 0.0
        
        points = points.enumerated().map {
            let y = $0.element.y - step
            
            if y > newMaxHeight {
                newMaxHeight = y
            }
            return CGPoint(x: $0.element.x, y: y)
        }
        
        currentMaxHeight = newMaxHeight
    }
    
    @MainActor func finished() {
        task?.cancel()
        self.isOn.toggle()
        completion()
    }
}

struct SplashView: View {
    @StateObject var splashManager: SplashManager
    let isHidden: Bool
    var authenticationIcon: Image {
        @Dependency(\.localAuthentication) var localAuthentication

        switch localAuthentication.method() {
        case .faceID: return Image(systemName: "faceid")
        case .touchID: return Image(systemName: "touchid")
        case .passcode: return Asset.Assets.Icons.authKey.image
        default: return Asset.Assets.Icons.coinsHand.image
        }
    }

    var authenticationDesc: String {
        @Dependency(\.localAuthentication) var localAuthentication

        switch localAuthentication.method() {
        case .faceID: return String(localizable: .splashAuthFaceID)
        case .touchID: return String(localizable: .splashAuthTouchID)
        case .passcode: return String(localizable: .splashAuthPasscode)
        default: return ""
        }
    }
    
    var hiIconYOffset: CGFloat {
        splashManager.lockScreen == .biometricRetry
        ? 100.0
        : 0.0
    }

    var hiHeight: CGFloat {
        var potentialCountryCode: String?
        
        if #available(iOS 16, *) {
            potentialCountryCode = Locale.current.language.languageCode?.identifier
        } else {
            potentialCountryCode = Locale.current.languageCode
        }
        
        if let potentialCountryCode, potentialCountryCode == "es" {
            return 0.6
        } else {
            return 0.35
        }
    }

    var body: some View {
        if splashManager.isOn && !isHidden {
            ZStack {
                hiIcon()
                lockContent()
            }
            .ignoresSafeArea(.keyboard)
        }
    }
    
    @ViewBuilder func hiIcon() -> some View {
        GeometryReader { proxy in
            Asset.Assets.welcomeScreenLogo.image
                .zImage(height: 60, color: .white)
                .position(
                    x: proxy.frame(in: .local).midX,
                    y: proxy.frame(in: .local).midY - hiIconYOffset
                )
        }
        .background(Asset.Colors.splash.color)
        .mask {
            SplashManager.SplashShape(points: splashManager.points)
        }
        .ignoresSafeArea()
        .onChange(of: isHidden) { value in
            if value {
                splashManager.preparePoints()
            }
        }
    }
    
    @ViewBuilder func lockContent() -> some View {
        switch splashManager.lockScreen {
        case .biometricRetry:
            VStack(spacing: 0) {
                Spacer()
                
                Button {
                    splashManager.authenticate()
                } label: {
                    authenticationIcon
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .foregroundColor(.white)
                }

                Text(localizable: .splashAuthTitle)
                    .font(.custom(FontFamily.Inter.semiBold.name, size: 20))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 24)

                Text(authenticationDesc)
                    .font(.custom(FontFamily.Inter.regular.name, size: 14))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(.bottom, 160)
            .screenHorizontalPadding()
        case .verifyPIN:
            AppPINEntryView(
                title: String(localizable: .appLockPINVerifyTitle),
                subtitle: String(localizable: .appLockPINVerifySubtitle),
                errorMessage: splashManager.errorMessage,
                digitCount: splashManager.pin.count,
                isInputEnabled: !splashManager.isProcessing && splashManager.lockoutSeconds == 0,
                onKey: splashManager.pinKeyTapped
            )
            .ignoresSafeArea()
        case .migrateCreatePIN, .migrateConfirmPIN:
            AppPINEntryView(
                title: splashManager.lockScreen == .migrateCreatePIN
                    ? String(localizable: .onboardingPINCreateTitle)
                    : String(localizable: .onboardingPINConfirmTitle),
                subtitle: splashManager.lockScreen == .migrateCreatePIN
                    ? String(localizable: .appLockMigrationPINSubtitle)
                    : String(localizable: .onboardingPINConfirmSubtitle),
                errorMessage: splashManager.errorMessage,
                digitCount: splashManager.pin.count,
                isInputEnabled: !splashManager.isProcessing,
                onKey: splashManager.pinKeyTapped
            )
            .ignoresSafeArea()
        case .none:
            EmptyView()
        }
    }
}

struct SplashModifier: ViewModifier {
    let isHidden: Bool
    let completion: () -> Void
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if isHidden {
                    SplashView(
                        splashManager: SplashManager(isHidden) {
                            completion()
                        },
                        isHidden: isHidden
                    )
                    .hidden()
                } else {
                    SplashView(
                        splashManager: SplashManager(isHidden) {
                            completion()
                        },
                        isHidden: isHidden
                    )
                }
            }
    }
}

extension View {
    func overlayedWithSplash(_ isHidden: Bool = false, completion: @escaping () -> Void) -> some View {
        modifier(SplashModifier(isHidden: isHidden, completion: completion))
    }
}
