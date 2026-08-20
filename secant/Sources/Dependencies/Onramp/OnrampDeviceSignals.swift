// SPDX-License-Identifier: MIT OR Apache-2.0

import Foundation
import Network
import SwiftUI
@preconcurrency import ZappOfframp

final class OnrampDeviceSignals: NSObject, AppleOnrampDeviceSignals, @unchecked Sendable {
    private let connection = OnrampConnectionSnapshot()

    override init() {
        super.init()
        connection.start()
    }

    func __collect(
        completionHandler: @escaping @Sendable (AppleOnrampDeviceSignalsRecord?, Error?) -> Void
    ) {
        Task { @MainActor [connection] in
            let snapshot = connection.snapshot
            completionHandler(Self.record(connectionType: snapshot.type, isOnline: snapshot.isOnline), nil)
        }
    }

    @MainActor static func record(
        connectionType: String?,
        isOnline: Bool = true,
        timeZone: TimeZone = .current,
        locale: Locale = .current,
        screen: UIScreen = .main,
        processInfo: ProcessInfo = .processInfo,
        device: UIDevice = .current,
        appVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    ) -> AppleOnrampDeviceSignalsRecord {
        let language = locale.identifier(.bcp47)
        let memoryGB = Double(processInfo.physicalMemory) / 1_073_741_824
        return AppleOnrampDeviceSignalsRecord(
            userAgent: "Zapp/\(appVersion ?? "") (iOS \(device.systemVersion); \(device.model))",
            platform: "iOS",
            language: language,
            languages: [language],
            screenWidth: Int32(screen.nativeBounds.width.rounded()),
            screenHeight: Int32(screen.nativeBounds.height.rounded()),
            devicePixelRatio: Double(screen.scale),
            timezone: timeZone.identifier,
            timezoneOffset: Int32(-(timeZone.secondsFromGMT() / 60)),
            cookiesEnabled: true,
            doNotTrack: nil,
            online: isOnline,
            touchSupport: true,
            maxTouchPoints: 5,
            vendor: "Apple",
            appVersion: appVersion ?? "",
            colorDepth: 24,
            pixelDepth: 24,
            connectionType: connectionType,
            deviceMemory: KotlinDouble(double: memoryGB),
            hardwareConcurrency: KotlinInt(int: Int32(processInfo.processorCount)),
            seonSession: nil
        )
    }
}

private final class OnrampConnectionSnapshot: @unchecked Sendable {
    struct Reading {
        let type: String?
        let isOnline: Bool
    }

    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.zapp.onramp.network-path")
    /// Reachability is a separate question from which transport carries it: a satisfied path over
    /// an interface we do not name is still online, and so is one collected before the monitor's
    /// first callback lands. Reporting either as offline would be a false fraud signal.
    private var current = Reading(type: nil, isOnline: true)

    var snapshot: Reading {
        lock.withLock { current }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let type: String?
            if path.status != .satisfied {
                type = nil
            } else if path.usesInterfaceType(.wifi) {
                type = "wifi"
            } else if path.usesInterfaceType(.wiredEthernet) {
                type = "ethernet"
            } else if path.usesInterfaceType(.cellular) {
                type = "4g"
            } else {
                type = nil
            }
            let reading = Reading(type: type, isOnline: path.status == .satisfied)
            self?.lock.withLock { self?.current = reading }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
