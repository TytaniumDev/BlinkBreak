//
//  FeedbackSheetView.swift
//  BlinkBreak
//
//  The feedback sheet opened from IdleView. Collects a category, an optional
//  reply-to email, and a message, and hands them to the `FeedbackReporting`
//  service from the environment (Sentry in production, a no-op in previews).
//

import SwiftUI

struct FeedbackSheetView: View {

    @Environment(\.dismiss) private var dismiss
    @Environment(\.feedbackReporter) private var reporter

    @State private var category: FeedbackCategory = .suggestion
    @State private var message = ""
    @State private var email = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let characterLimit = 1000

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isOverLimit: Bool { message.count > characterLimit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Share Your Thoughts")
                            .font(.title2.weight(.bold))
                        Text("Your feedback helps shape BlinkBreak. We read every submission!")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    field("Category") {
                        HStack(spacing: 8) {
                            ForEach(FeedbackCategory.allCases) { option in
                                CategoryButton(category: option, isSelected: category == option) {
                                    withAnimation(.spring(duration: 0.25)) { category = option }
                                }
                            }
                        }
                    }

                    field("Email Address (Optional)") {
                        TextField("you@example.com", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .padding(12)
                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.1)))
                    }

                    field("Comments", trailing: "\(message.count)/\(characterLimit)") {
                        TextEditor(text: $message)
                            .font(.subheadline)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 140)
                            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isOverLimit ? .red : .white.opacity(0.1))
                            )
                            .accessibilityLabel("Comments")
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button(action: submit) {
                        HStack {
                            if isSubmitting {
                                ProgressView()
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
                    .disabled(isSubmitting || trimmedMessage.isEmpty || isOverLimit)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("button.feedback.submit")

                    Text("Diagnostic data and recent app logs are attached automatically to help us "
                         + "understand any issues. No personal data is shared.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(Layout.screenPadding)
                .frame(maxWidth: Layout.readableWidth)
                .frame(maxWidth: .infinity)
            }
            .background(CalmBackground())
            .foregroundStyle(.white)
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationSizing(.form)
        .preferredColorScheme(.dark)
    }

    private func field<Content: View>(
        _ title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .foregroundStyle(isOverLimit ? .red : .white.opacity(0.4))
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        let replyTo = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSubmitting = false }
            do {
                try await reporter.submit(
                    category: category,
                    message: trimmedMessage,
                    email: replyTo.isEmpty ? nil : replyTo
                )
                dismiss()
            } catch {
                errorMessage = "Failed to send feedback. Please try again."
            }
        }
    }
}

/// One of the category chips at the top of the sheet.
private struct CategoryButton: View {
    let category: FeedbackCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: category.systemImage)
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
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    FeedbackSheetView()
}
