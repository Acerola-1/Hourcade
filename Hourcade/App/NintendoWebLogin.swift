import AppKit
import AuthenticationServices

@MainActor
final class NintendoWebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = NintendoWebLogin()
    private var session: ASWebAuthenticationSession?
    private var activeAttemptID: UUID?
    private var continuation: CheckedContinuation<NintendoAPI.LoginCode, Error>?

    func authorize() async throws -> NintendoAPI.LoginCode {
        let attemptID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard activeAttemptID == nil else { throw NintendoLoginError.alreadyInProgress }
            let login = NintendoAPI.makeLoginRequest()
            return try await withCheckedThrowingContinuation { continuation in
                // Cancellation can arrive between entering the handler and registering this attempt.
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                activeAttemptID = attemptID
                self.continuation = continuation
                let auth = ASWebAuthenticationSession(
                    url: login.url,
                    callbackURLScheme: NintendoAPI.callbackURLScheme
                // The system invokes this on its own queue; hop back before touching state.
                ) { @Sendable [weak self] callbackURL, error in
                    Task { @MainActor [weak self] in
                        guard let self, self.activeAttemptID == attemptID else { return }
                        if let error {
                            let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                            self.finish(attemptID, with: .failure(
                                cancelled ? NintendoLoginError.cancelled : NintendoLoginError.couldNotComplete
                            ))
                            return
                        }
                        guard let callbackURL else {
                            self.finish(attemptID, with: .failure(NintendoLoginError.missingCallback))
                            return
                        }
                        do {
                            let code = try NintendoAPI.sessionTokenCode(from: callbackURL, expectedState: login.state)
                            self.finish(attemptID, with: .success(
                                NintendoAPI.LoginCode(code: code, verifier: login.codeVerifier)
                            ))
                        } catch {
                            self.finish(attemptID, with: .failure(error))
                        }
                    }
                }
                // Non-ephemeral on purpose: Nintendo's account page offers one-tap
                // account picking when the browser is already signed in, and the
                // session token this flow yields lasts about two years either way.
                auth.prefersEphemeralWebBrowserSession = false
                auth.presentationContextProvider = self
                session = auth
                if !auth.start() {
                    finish(attemptID, with: .failure(NintendoLoginError.couldNotStart))
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                self?.finish(attemptID, with: .failure(CancellationError()))
            }
        }
    }

    private func finish(_ attemptID: UUID, with result: Result<NintendoAPI.LoginCode, Error>) {
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

private enum NintendoLoginError: LocalizedError {
    case alreadyInProgress, cancelled, missingCallback, invalidCallback, couldNotStart, couldNotComplete

    var errorDescription: String? {
        switch self {
        case .alreadyInProgress: L10n.tr("Nintendo 登录已在进行中，请先完成或取消当前登录")
        case .cancelled: L10n.tr("已取消 Nintendo 登录")
        case .missingCallback: L10n.tr("Nintendo 登录完成，但没有返回授权码")
        case .invalidCallback: L10n.tr("Nintendo 登录回调验证失败，请重新登录")
        case .couldNotStart: L10n.tr("无法打开 Nintendo 登录窗口")
        case .couldNotComplete: L10n.tr("Nintendo 登录未能完成，请重试")
        }
    }
}
