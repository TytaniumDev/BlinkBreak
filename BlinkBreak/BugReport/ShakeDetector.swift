//
//  ShakeDetector.swift
//  BlinkBreak
//
//  Detects shake gestures and presents a bug report submission dialog.
//  TestFlight-only: production builds ignore shakes entirely.
//
//  Flutter analogue: like wrapping your root widget in a GestureDetector
//  that listens for device shake events.
//

import SwiftUI
import BlinkBreakCore

/// Invisible UIKit view controller that intercepts shake gestures. Layered into the
/// SwiftUI view hierarchy via `ShakeDetectorView`.
final class ShakeDetectingViewController: UIViewController {

    var onShake: (() -> Void)?

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            onShake?()
        }
    }

    // Must be first responder to receive motion events.
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
}

/// SwiftUI wrapper that layers an invisible shake-detecting UIKit controller behind
/// the content. Only active in TestFlight builds.
struct ShakeDetectorView<Content: View>: View {

    let content: Content
    let persistence: PersistenceProtocol
    let sessionState: SessionState

    @State private var showingSubmitAlert = false
    @State private var bugDescription = ""
    @State private var showingToast = false
    @State private var toastMessage = ""
    @State private var isSubmitting = false

    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    var body: some View {
        content
            .background(
                ShakeDetectorRepresentable {
                    guard isTestFlight else { return }
                    showingSubmitAlert = true
                    bugDescription = ""
                }
            )
            .alert("Report a Bug", isPresented: $showingSubmitAlert) {
                TextField("Describe the issue", text: $bugDescription)
                Button("Cancel", role: .cancel) {}
                Button("Send") {
                    submitReport()
                }
                .disabled(isSubmitting)
            } message: {
                Text("Your report will create a GitHub issue with diagnostic data (no personal info).")
            }
            .overlay(alignment: .bottom) {
                if showingToast {
                    Text(toastMessage)
                        .font(.footnote)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 40)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showingToast)
    }

    private func submitReport() {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }

            do {
                let deviceInfo = DeviceInfo(
                    iosVersion: UIDevice.current.systemVersion,
                    deviceModel: Self.deviceModelIdentifier(),
                    appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
                    buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
                    isTestFlight: isTestFlight
                )

                let collector = DiagnosticCollector(
                    persistence: persistence,
                    logBuffer: LogBuffer.shared,
                    sessionState: sessionState
                )

                let report = await collector.collect(deviceInfo: deviceInfo)

                guard let token = BugReportConfig.gitHubToken else {
                    showToast("Bug reporting not configured")
                    return
                }

                let reporter = GitHubIssueReporter(
                    token: token,
                    repo: BugReportConfig.gitHubRepo
                )
                try await reporter.submit(
                    report: report,
                    userDescription: bugDescription
                )

                showToast("Report sent")
            } catch {
                showToast("Failed to send report")
            }
        }
    }

    private func showToast(_ message: String) {
        toastMessage = message
        showingToast = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            showingToast = false
        }
    }

    /// Returns the machine identifier (e.g. "iPhone15,2") instead of the marketing
    /// name. Avoids importing the user-facing device name which could be PII.
    private static func deviceModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
    }
}

/// UIViewControllerRepresentable bridge for the shake-detecting UIKit controller.
private struct ShakeDetectorRepresentable: UIViewControllerRepresentable {
    let onShake: () -> Void

    func makeUIViewController(context: Context) -> ShakeDetectingViewController {
        let vc = ShakeDetectingViewController()
        vc.onShake = onShake
        return vc
    }

    func updateUIViewController(_ uiViewController: ShakeDetectingViewController, context: Context) {
        uiViewController.onShake = onShake
    }
}
