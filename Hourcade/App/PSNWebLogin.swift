import AppKit
import AuthenticationServices

@MainActor
final class PSNWebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PSNWebLogin()
    private var session: ASWebAuthenticationSession?
    private var activeAttemptID: UUID?
    private var continuation: CheckedContinuation<String, Error>?

    func authorize() async throws -> String {
        let attemptID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard activeAttemptID == nil else { throw PSNLoginError.alreadyInProgress }
            let state = UUID().uuidString
            return try await withCheckedThrowingContinuation { continuation in
                // Cancellation can arrive between entering the handler and registering this attempt.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                activeAttemptID = attemptID
                self.continuation = continuation
                let auth = ASWebAuthenticationSession(
                    url: PSNAPI.authorizationURL(state: state),
                    callbackURLScheme: PSNAPI.callbackURLScheme
                // ASWebAuthenticationSession invokes this block on its own XPC queue, not
                // the main actor. @Sendable keeps it nonisolated so it does not trap on
                // entry; the body hops back with Task { @MainActor }.
                ) { @Sendable [weak self] callbackURL, error in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeAttemptID == attemptID else { return }
                        if let error {
                            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                            self.finish(attemptID, with: .failure(
                                cancelled ? PSNLoginError.cancelled : PSNLoginError.couldNotComplete
                            ))
                            return
                        }
                        guard let callbackURL else {
                            self.finish(attemptID, with: .failure(PSNLoginError.missingCallback))
                            return
                        }
                        do {
                            // Validate the exact scheme, host, path and state, then code/error exclusivity.
                            let code = try PSNAPI.authorizationCode(from: callbackURL, expectedState: state)
                            self.finish(attemptID, with: .success(code))
                        } catch {
                            self.finish(attemptID, with: .failure(error))
                        }
                    }
                }
                auth.presentationContextProvider = self
                auth.prefersEphemeralWebBrowserSession = true
                session = auth
                if !auth.start() {
                    finish(attemptID, with: .failure(PSNLoginError.couldNotStart))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finish(attemptID, with: .failure(CancellationError()))
            }
        }
    }

    private func finish(_ attemptID: UUID, with result: Result<String, Error>) {
        guard activeAttemptID == attemptID, let continuation else { return }
        let completedSession = session
        // Clear identity and continuation before cancel(), which may trigger another callback.
        activeAttemptID = nil
        self.continuation = nil
        session = nil
        completedSession?.cancel()
        continuation.resume(with: result)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.mainWindow ?? NSWindow()
    }
}

private enum PSNLoginError: LocalizedError {
    case alreadyInProgress, cancelled, missingCallback, couldNotStart, couldNotComplete

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress: L10n.tr("PlayStation 登录已在进行中，请先完成或取消当前登录")
        case .cancelled: L10n.tr("已取消 PlayStation 登录")
        case .missingCallback: L10n.tr("PlayStation 登录完成，但没有返回授权码")
        case .couldNotStart: L10n.tr("无法打开 PlayStation 登录窗口")
        case .couldNotComplete: L10n.tr("PlayStation 登录未能完成，请重试")
        }
    }
}
