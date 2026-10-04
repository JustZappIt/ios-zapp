//
//  ChatRoomLocation.swift
//  Zapp
//
//  The media sheet's "Location" tile — Android's `onShareLocationClick` →
//  `ChatRoomEffectsHandler.shareLocation` → `ChatRoomVM.sendLocationMessage`.
//
//  Flow: the tile parks `pendingLocationShare` and closes the sheet (see
//  `ChatRoomAttachments.swift`); once the sheet is gone the permission is resolved, then one fix
//  is taken and posted as `application/location`. Every failure lands in the room's failure
//  strip with Android's toast copy; a refused permission also offers "Open settings".
//

import ComposableArchitecture
import Foundation

extension ChatRoom {
    func requestLocationAuthorization() -> Effect<Action> {
        @Dependency(\.location) var location

        return .run { send in
            let granted = location.isAuthorized()
                ? true
                : await location.requestAuthorization()

            await send(.locationAuthorizationResolved(granted))
        }
    }

    func locationReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {
            case .locationAuthorizationResolved(let granted):
                guard granted else {
                    state.sendDidFail = true
                    state.sendFailureMessage = String(localizable: .chatRoomLocationPermissionRequired)
                    return .none
                }

                // One attachment at a time, the same guard the picker paths take.
                guard !state.isSendingMedia else { return .none }

                state.isSendingMedia = true
                state.sendDidFail = false
                state.sendFailureMessage = nil

                return shareLocation(conversationId: state.conversationId)

            case .attachmentFailed(let message):
                state.isSendingMedia = false
                state.sendDidFail = true
                state.sendFailureMessage = message
                return .none

            default:
                return .none
            }
        }
    }

    private func shareLocation(conversationId: String) -> Effect<Action> {
        @Dependency(\.location) var location

        return .run { send in
            let fix: LocationFix

            do {
                fix = try await location.currentLocation()
            } catch {
                LoggerProxy.error("Chat room failed to get a location fix: \(error)")
                await send(.attachmentFailed(Self.failureMessage(for: error)))
                return
            }

            guard let payload = ChatLocation.json(
                latitude: fix.latitude,
                longitude: fix.longitude,
                accuracy: fix.accuracy
            ) else {
                await send(.attachmentFailed(String(localizable: .chatRoomLocationUnavailable)))
                return
            }

            let message = try await zappMessaging.sendLocation(conversationId, payload)
            await send(.mediaSendSucceeded(message))
        } catch: { error, send in
            // Only the send itself reaches here; a fix failure returned above with its own copy.
            LoggerProxy.error("Chat room failed to send location: \(error)")
            await send(.mediaSendFailed)
        }
    }

    /// Android's three toasts: refused permission, no fix ("Could not get location"), and
    /// anything else ("Location error: %1$s").
    static func failureMessage(for error: Error) -> String {
        switch error as? LocationFailure {
        case .notAuthorized:
            return String(localizable: .chatRoomLocationPermissionRequired)
        case .failed(let reason):
            return String(localizable: .chatRoomLocationError(reason))
        case .unavailable, .none:
            return String(localizable: .chatRoomLocationUnavailable)
        }
    }
}
