//
//  GoogleCalendarAccount.swift
//  BlinkBreak
//
//  The signed-in Google account used for meeting skipping. The only file that
//  imports GoogleSignIn. Wraps `GIDSignIn` for two clients:
//
//  - Views, through `GoogleAccountConnecting` (connect / disconnect, show the email).
//  - `GoogleCalendarProvider`, which asks for a fresh access token before each call.
//
//  GoogleSignIn keeps the tokens in the keychain and refreshes them, so the
//  account survives relaunches and works when an alarm button wakes the app.
//
//  Flutter analogue: a ChangeNotifier around the `google_sign_in` plugin.
//

import GoogleSignIn
import Observation
import UIKit

@MainActor
@Observable
final class GoogleCalendarAccount: GoogleAccountConnecting {

    /// The signed-in account's email, or nil when not connected.
    private(set) var email: String?

    /// Fires when the account connects or disconnects, so the calendar is re-checked.
    nonisolated let changes: AsyncStream<Void>
    private let changesContinuation: AsyncStream<Void>.Continuation

    private var signIn: GIDSignIn { GIDSignIn.sharedInstance }

    /// Resumed with the signed-in email and the scopes the user granted.
    private typealias SignInContinuation = CheckedContinuation<(String?, [String]), Error>

    init() {
        (changes, changesContinuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// True when signed in now, or a sign-in is stored and can be restored.
    var isConnected: Bool {
        signIn.currentUser != nil || signIn.hasPreviousSignIn()
    }

    /// Restore the stored sign-in, if any. Call at launch.
    func restore() async {
        guard signIn.currentUser == nil, signIn.hasPreviousSignIn() else {
            email = signIn.currentUser?.profile?.email
            return
        }
        do {
            email = try await withCheckedThrowingContinuation { continuation in
                signIn.restorePreviousSignIn { user, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: user?.profile?.email)
                    }
                }
            }
        } catch {
            AppLogger.shared.log(.warning, "google: restore failed: \(error)")
        }
    }

    func connect() async throws {
        guard let presenter = Self.presentingViewController() else { return }
        let email: String?
        let grantedScopes: [String]
        do {
            (email, grantedScopes) = try await withCheckedThrowingContinuation { (continuation: SignInContinuation) in
                signIn.signIn(withPresenting: presenter, hint: nil, additionalScopes: GoogleCalendarAPI.scopes) { result, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: (result?.user.profile?.email, result?.user.grantedScopes ?? []))
                    }
                }
            }
        } catch let error as GIDSignInError where error.code == .canceled {
            return
        }
        guard Set(GoogleCalendarAPI.scopes).isSubset(of: grantedScopes) else {
            // The consent screen lets people untick scopes.
            signIn.signOut()
            throw GoogleAccountError.calendarAccessNotGranted
        }
        self.email = email
        AppLogger.shared.log(.info, "google: connected")
        changesContinuation.yield()
    }

    func disconnect() async {
        // Revokes the app's access too, not just the local sign-in.
        await withCheckedContinuation { continuation in
            signIn.disconnect { _ in continuation.resume() }
        }
        signIn.signOut()
        email = nil
        AppLogger.shared.log(.info, "google: disconnected")
        changesContinuation.yield()
    }

    /// Finish a sign-in that came back through the app's URL scheme.
    func handle(_ url: URL) {
        _ = signIn.handle(url)
    }

    /// A valid access token, refreshed if needed, or nil when not connected
    /// (or the refresh failed, e.g. offline).
    func accessToken() async -> String? {
        if signIn.currentUser == nil {
            await restore()
        }
        guard let user = signIn.currentUser else { return nil }
        return await withCheckedContinuation { continuation in
            user.refreshTokensIfNeeded { user, error in
                if let error {
                    AppLogger.shared.log(.warning, "google: token refresh failed: \(error)")
                }
                continuation.resume(returning: user?.accessToken.tokenString)
            }
        }
    }

    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

enum GoogleAccountError: LocalizedError {
    case calendarAccessNotGranted

    var errorDescription: String? {
        switch self {
        case .calendarAccessNotGranted:
            return "BlinkBreak needs permission to see your calendars' busy times."
        }
    }
}
