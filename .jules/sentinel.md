## 2025-02-18 - [Fix Markdown Injection in BugReporter]
**Vulnerability:** The `userDescription` field submitted in the bug report inside `GitHubIssueReporter` was not sanitized before being injected into a markdown template.
**Learning:** Input submitted by users via a frontend can contain harmful payloads (like HTML/Markdown injections) that can break formats or perform XSS if viewed on GitHub issues.
**Prevention:** Ensure that all user inputs inserted into structured formats (like Markdown, HTML, JSON) are properly escaped or sanitized (e.g., replacing `<` with `&lt;`).

## 2024-05-24 - [Add timeout and input limits to external network dependencies]
**Vulnerability:** Found `GitHubIssueReporter.swift` lacked an explicit timeout in its `URLRequest` and accepted an unconstrained `userDescription` string for the bug report body. This could lead to hanging connections (resource exhaustion) and large payload DoS when communicating with the GitHub API.
**Learning:** Network dependencies in this codebase must always explicitly set `timeoutInterval` and bound user input length to prevent denial-of-service vectors, even if the feature is scoped to TestFlight users.
**Prevention:** Always configure an explicit `.timeoutInterval` on `URLRequest` instances and use `.prefix()` to truncate arbitrary user input strings before serializing them into network payloads.

## 2024-05-25 - [Sanitize and Bound Log Buffer Contents]
**Vulnerability:** The LogBuffer accepted unbounded log messages, and the BugReporter did not sanitize triple backticks (` ``` `) from log entry messages before embedding them in the Markdown body of the GitHub issue.
**Learning:** This combination could lead to Memory Exhaustion (DoS via large log sizes keeping them in memory) and Markdown Injection (where an unescaped triple backtick breaks out of the intended details `<details>` code block).
**Prevention:** Bound unbounded strings (using `.prefix(1000)`) before retaining them in memory, and specifically sanitize inputs before placing them into formatted contexts (like Markdown code blocks or HTML).

## 2024-05-26 - [Prevent concurrent API submissions from ShakeDetector]
**Vulnerability:** The bug report submission UI (`ShakeDetectorView`) allowed the user to tap "Send" multiple times rapidly while the async submission Task was running. This could cause concurrent network requests, potentially triggering GitHub API rate limiting or creating duplicate issues.
**Learning:** Client-side rate limiting and UI-level debounce are essential to protect backend infrastructure and prevent redundant operations when relying on asynchronous network calls triggered by user interaction.
**Prevention:** Implement a local state flag (e.g., `@State private var isSubmitting = false`) to disable the submission UI button during the in-flight request, and add a guard within the submit action itself to abort if already submitting.

## 2026-04-22 - [Fix Markdown injection and mention spam in bug reports]
**Vulnerability:** The bug reporting tool accepted unescaped markdown characters (like ```) in the user description, and did not wrap the description in a fenced code block, opening vectors for Markdown injection such as `@mentions` (notification spam) or Server-Side Request Forgery via image loading.
**Learning:** When passing untrusted user input into Markdown-rendering APIs (like GitHub Issues), standard HTML sanitization (`<` and `>`) is insufficient. Markdown-specific constructs can be abused to trigger unwanted actions on the hosting platform.
**Prevention:** Wrap raw user inputs in fenced code blocks (e.g., ` ```text `) when rendering them in Markdown templates, and sanitize backticks (```) within the input to prevent code block breakout attacks.

## 2025-02-18 - [Bound user input length sent to third-party SDKs]
**Vulnerability:** The bug reporting tool passed an unbounded `userDescription` string directly into the Sentry SDK (`SentryFeedback`). This could lead to massive payload denial-of-service if a malicious user pasted extremely large text into the feedback field.
**Learning:** Third-party SDKs do not necessarily bound input sizes for you. Passing unconstrained strings to analytics or crash-reporting libraries can exhaust memory or cause dropped payloads on the backend.
**Prevention:** Always bound raw user inputs with `.prefix()` before passing them into third-party SDKs or logging frameworks, even if you are not managing the network request yourself.
