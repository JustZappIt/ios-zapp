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
            completionHandler(Self.record(connectionType: connection.type), nil)
        }
    }

    @MainActor static func record(
        connectionType: String?,
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
            online: connectionType != nil,
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
    private let lock = NSLock()
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.zapp.onramp.network-path")
    private var currentType: String?

    var type: String? {
        lock.withLock { currentType }
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let value: String?
            if path.status != .satisfied {
                value = nil
            } else if path.usesInterfaceType(.wifi) {
                value = "wifi"
            } else if path.usesInterfaceType(.wiredEthernet) {
                value = "ethernet"
            } else if path.usesInterfaceType(.cellular) {
                value = "4g"
            } else {
                value = nil
            }
            self?.lock.withLock { self?.currentType = value }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
