import AppKit
import AuthenticationServices

@MainActor
final class PSNWebLogin: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = PSNWebLogin()
    private var session: ASWebAuthenticationSession?

    func authorize() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(
                url: PSNAPI.authorizationURL,
                callbackURLScheme: "com.scee.psxandroid.scecompcall"
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.session = nil
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let callbackURL,
                          let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "code" })?.value
                    else {
                        continuation.resume(throwing: PSNLoginError.missingCode)
                        return
                    }
                    continuation.resume(returning: code)
                }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            session = auth
            if !auth.start() {
                session = nil
                continuation.resume(throwing: PSNLoginError.couldNotStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSWindow()
    }
}

private enum PSNLoginError: LocalizedError {
    case missingCode, couldNotStart
    var errorDescription: String? {
        switch self {
        case .missingCode: "PlayStation 登录完成，但没有返回授权码"
        case .couldNotStart: "无法打开 PlayStation 登录窗口"
        }
    }
}
