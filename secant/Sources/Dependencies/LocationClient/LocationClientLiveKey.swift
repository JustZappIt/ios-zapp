//
//  LocationClientLiveKey.swift
//  Zapp
//

import ComposableArchitecture
@preconcurrency import CoreLocation
import Foundation

extension LocationClient: DependencyKey {
    static let liveValue = Self(
        isAuthorized: {
            isGranted(CLLocationManager().authorizationStatus)
        },
        requestAuthorization: { @MainActor in
            await OneShotLocationRequest().authorize()
        },
        currentLocation: { @MainActor in
            try await OneShotLocationRequest().locate()
        }
    )

    static func isGranted(_ status: CLAuthorizationStatus) -> Bool {
        status == .authorizedWhenInUse || status == .authorizedAlways
    }
}

/// One `CLLocationManager` per request, alive until its continuation resumes. Core Location calls
/// the delegate on the thread that created the manager, so everything here is main-actor bound.
@MainActor
private final class OneShotLocationRequest: NSObject, CLLocationManagerDelegate {
    /// Android's `getCurrentLocation` has no explicit timeout, but a high-accuracy request indoors
    /// can stall for a long time. Past this the user gets "Could not get location".
    private static let timeout: Duration = .seconds(20)

    private let manager = CLLocationManager()
    private var authorization: CheckedContinuation<Bool, Never>?
    private var fix: CheckedContinuation<LocationFix, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func authorize() async -> Bool {
        switch manager.authorizationStatus {
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                authorization = continuation
                manager.requestWhenInUseAuthorization()
            }

        default:
            // Denied or restricted: iOS never re-prompts, so the caller surfaces the refusal.
            return LocationClient.isGranted(manager.authorizationStatus)
        }
    }

    func locate() async throws -> LocationFix {
        try await withCheckedThrowingContinuation { continuation in
            fix = continuation
            manager.requestLocation()

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: Self.timeout)
                guard !Task.isCancelled else { return }
                self?.finish(.failure(LocationFailure.unavailable))
            }
        }
    }

    private func finish(_ result: Result<LocationFix, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        manager.stopUpdatingLocation()

        guard let fix else { return }
        self.fix = nil
        fix.resume(with: result)
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        MainActor.assumeIsolated {
            // The first callback fires on creation with the current status; only a decided
            // status answers the prompt.
            guard status != .notDetermined, let authorization else { return }
            self.authorization = nil
            authorization.resume(returning: LocationClient.isGranted(status))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // A negative accuracy marks the coordinate itself as invalid.
        let located = locations
            .last { $0.horizontalAccuracy >= 0 && CLLocationCoordinate2DIsValid($0.coordinate) }
            .map {
                LocationFix(
                    latitude: $0.coordinate.latitude,
                    longitude: $0.coordinate.longitude,
                    accuracy: $0.horizontalAccuracy
                )
            }

        MainActor.assumeIsolated {
            finish(located.map { .success($0) } ?? .failure(LocationFailure.unavailable))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let failure: LocationFailure

        switch (error as? CLError)?.code {
        case .denied: failure = .notAuthorized
        case .locationUnknown, .network: failure = .unavailable
        default: failure = .failed(error.localizedDescription)
        }

        MainActor.assumeIsolated {
            finish(.failure(failure))
        }
    }
}
