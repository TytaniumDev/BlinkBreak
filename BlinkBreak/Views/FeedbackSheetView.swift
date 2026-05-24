//
//  FeedbackSheetView.swift
//  BlinkBreak
//
//  A premium, high-fidelity feedback submission sheet for BlinkBreak.
//  Enables users to submit suggestions, bug reports, questions, or general feedback
//  directly to Sentry (where Jules can read it), packaged with rich diagnostic details
//  and local log history.
//

import SwiftUI
import BlinkBreakCore
import Sentry

/// A beautiful modal sheet that collects structured user feedback and sends it to Sentry.
struct FeedbackSheetView: View {

    @Environment(\.dismiss) private var dismiss

    let persistence: PersistenceProtocol
    let sessionState: SessionState

    @State private var selectedCategory: FeedbackCategory = .suggestion
    @State private var feedbackText = ""
    @State private var emailAddress = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil

    private let characterLimit = 1000

    private var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Sleek, matching dark palette background
                LinearGradient(
                    colors: [
                        Color(red: 0.04, green: 0.06, blue: 0.08),
                        Color(red: 0.02, green: 0.10, blue: 0.12)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Title / Intro
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Share Your Thoughts")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                            
                            Text("Your feedback helps shape BlinkBreak. We read every submission!")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        .padding(.top, 10)

                        // Category Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Category")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(1)

                            HStack(spacing: 8) {
                                ForEach(FeedbackCategory.allCases) { category in
                                    CategoryButton(
                                        category: category,
                                        isSelected: selectedCategory == category
                                    ) {
                                        withAnimation(.spring(duration: 0.25)) {
                                            selectedCategory = category
                                        }
                                    }
                                }
                            }
                        }

                        // Contact Email (Optional)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address (Optional)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.5))
                                .tracking(1)

                            TextField("jules@example.com", text: $emailAddress)
                                .textFieldStyle(.plain)
                                .keyboardType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(.white.opacity(0.1), lineWidth: 1)
                                )
                                .foregroundStyle(.white)
                        }

                        // Feedback description box
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Comments")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .tracking(1)
                                Spacer()
                                Text("\(feedbackText.count)/\(characterLimit)")
                                    .font(.caption)
                                    .foregroundStyle(feedbackText.count > characterLimit ? .red : .white.opacity(0.4))
                            }

                            ZStack(alignment: .topLeading) {
                                if feedbackText.isEmpty {
                                    Text("What's on your mind? Tell us what you like or how we can improve...")
                                        .font(.subheadline)
                                        .foregroundStyle(.white.opacity(0.25))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 12)
                                        .allowsHitTesting(false)
                                }

                                TextEditor(text: $feedbackText)
                                    .font(.subheadline)
                                    .foregroundStyle(.white)
                                    .scrollContentBackground(.hidden) // make background transparent
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .frame(minHeight: 140)
                                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(feedbackText.count > characterLimit ? .red : .white.opacity(0.1), lineWidth: 1)
                                    )
                            }
                        }

                        if let errorMessage = errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .padding(.top, 4)
                        }

                        // Submit action
                        Button {
                            submitFeedback()
                        } label: {
                            HStack {
                                if isSubmitting {
                                    ProgressView()
                                        .tint(.black)
                                        .padding(.trailing, 8)
                                }
                                Text(isSubmitting ? "Sending..." : "Submit Feedback")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.green)
                        .disabled(isSubmitting || feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || feedbackText.count > characterLimit)
                        .accessibilityIdentifier("button.feedback.submit")
                        .padding(.top, 10)
                        
                        Text("Diagnostic data and log snapshots are attached automatically to help us understand any issues. No personal data is shared.")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
    }

    private func submitFeedback() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

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

                // Prefix the description with the selected category for easy filtering in Sentry UI
                let prefix = "[\(selectedCategory.rawValue.uppercased())]"
                var finalDescription = "\(prefix) \(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines))"
                
                // Securely sanitize any triple backticks within user text to prevent Markdown breakage/injection
                // in external rendering scopes.
                finalDescription = finalDescription.replacingOccurrences(of: "```", with: "\\`\\`\\`")

                // Inject companion user info if email is provided
                let email = emailAddress.trimmingCharacters(in: .whitespacesAndNewlines)

                // Instantiate Sentry reporter and submit
                let reporter = SentryFeedbackReporter()
                
                // Using an associated user block if email is provided
                if !email.isEmpty {
                    let user = User()
                    user.email = email
                    SentrySDK.setUser(user)
                }

                defer {
                    // Ensure temporary email is cleared from Sentry global scope even if submission throws
                    if !email.isEmpty {
                        SentrySDK.setUser(nil)
                    }
                }

                try await reporter.submit(
                    report: report,
                    userDescription: finalDescription
                )

                // Successful submission, close the sheet
                dismiss()
            } catch {
                errorMessage = "Failed to send feedback. Please try again."
            }
        }
    }

    /// Returns the machine identifier (e.g. "iPhone15,2") instead of the marketing name
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

/// The available feedback types
enum FeedbackCategory: String, CaseIterable, Identifiable {
    case suggestion = "Suggestion"
    case bugReport = "Bug Report"
    case question = "Question"
    case other = "Other"

    var id: String { self.rawValue }

    var icon: String {
        switch self {
        case .suggestion: return "lightbulb.fill"
        case .bugReport: return "ladybug.fill"
        case .question: return "questionmark.circle.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

#Preview {
    FeedbackSheetView(
        persistence: InMemoryPersistence(),
        sessionState: .idle
    )
    .preferredColorScheme(.dark)
}

/// A custom-styled horizontal button for selecting feedback categories
private struct CategoryButton: View {
    let category: FeedbackCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.title3)
                Text(category.rawValue)
                    .font(.caption2.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.green.opacity(0.2) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.green : Color.white.opacity(0.1), lineWidth: 1.5)
            )
        }
    }
}
