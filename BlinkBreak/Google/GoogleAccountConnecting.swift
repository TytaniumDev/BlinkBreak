//
//  GoogleAccountConnecting.swift
//  BlinkBreak
//
//  What views can do with the Google account, injected through the SwiftUI
//  environment so views never touch the GoogleSignIn SDK. Production uses
//  `GoogleCalendarAccount`; previews use `PreviewGoogleAccount`. Nil (the
//  default) hides the Google row.
//
//  Flutter analogue: an abstract service provided with `Provider<GoogleAccount?>`.
//

import Observation
import SwiftUI

@MainActor
protocol GoogleAccountConnecting: AnyObject, Observable, Sendable {
    /// The connected account's email, or nil when not connected.
    var email: String? { get }
    /// Show Google's sign-in and ask for read-only calendar access.
    func connect() async throws
    /// Sign out and revoke BlinkBreak's access.
    func disconnect() async
}

extension EnvironmentValues {
    @Entry var googleAccount: (any GoogleAccountConnecting)? = nil
}

/// For previews: connects instantly as a fake account.
@MainActor
@Observable
final class PreviewGoogleAccount: GoogleAccountConnecting {
    var email: String?

    init(email: String? = nil) {
        self.email = email
    }

    func connect() async throws {
        email = "name@gmail.com"
    }

    func disconnect() async {
        email = nil
    }
}
