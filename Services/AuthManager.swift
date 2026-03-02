import AuthenticationServices
import Foundation
import SwiftUI

@Observable
final class AuthManager {
    var isAuthenticated: Bool = false
    var userEmail: String?
    var userName: String?
    var isAuthenticating: Bool = false
    var authError: String?

    private let apiClient: APIClient
    private var currentAuthSession: ASWebAuthenticationSession?
    private var contextProvider: WebAuthContextProvider?

    init(apiClient: APIClient = APIClient()) {
        self.apiClient = apiClient
    }

    func restoreSession() {
        if let token = KeychainHelper.read(.authToken), !token.isEmpty {
            isAuthenticated = true
            userEmail = KeychainHelper.read(.userEmail)
            userName = KeychainHelper.read(.userName)
        }
    }

    /// First name for greeting — from stored name or derived from email
    var firstName: String? {
        if let name = userName, !name.isEmpty {
            return name.components(separatedBy: " ").first
        }
        if let email = userEmail {
            let local = email.components(separatedBy: "@").first ?? email
            var name = local.components(separatedBy: ".").first ?? local
            // Strip trailing digits (e.g. "gurjeet2797" → "gurjeet")
            while let last = name.last, last.isNumber {
                name.removeLast()
            }
            guard !name.isEmpty else { return nil }
            return name.capitalized
        }
        return nil
    }

    func signInWithGoogle() async {
        isAuthenticating = true
        authError = nil

        do {
            let authURL = try await apiClient.startGoogleAuth()
            let callbackURL = try await startWebAuthSession(url: authURL)
            try handleCallback(url: callbackURL)
        } catch {
            if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                // User cancelled — not an error
            } else {
                authError = error.localizedDescription
            }
        }

        isAuthenticating = false
    }

    func updateName(_ newName: String) {
        KeychainHelper.save(newName, for: .userName)
        userName = newName
    }

    func signOut() {
        KeychainHelper.deleteAll()
        isAuthenticated = false
        userEmail = nil
        userName = nil
    }

    func handleDeepLink(url: URL) throws {
        try handleCallback(url: url)
    }

    // MARK: - Private

    @MainActor
    private func startWebAuthSession(url: URL) async throws -> URL {
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            // Explicit @Sendable prevents this closure from inheriting @MainActor.
            // ASWebAuthenticationSession fires it on a background thread.
            let handler: @Sendable (URL?, (any Error)?) -> Void = { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: APIError.invalidURL)
                }
            }
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(APIConfig.customURLScheme),
                completionHandler: handler
            )
            session.prefersEphemeralWebBrowserSession = false

            let provider = WebAuthContextProvider()
            session.presentationContextProvider = provider

            self.contextProvider = provider
            self.currentAuthSession = session

            session.start()
        }
        // Clean up on @MainActor after continuation resumes
        currentAuthSession = nil
        contextProvider = nil
        return callbackURL
    }

    private func handleCallback(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        let params = components.queryItems?.reduce(into: [String: String]()) { dict, item in
            dict[item.name] = item.value
        } ?? [:]

        if let error = params["error"], !error.isEmpty {
            throw APIError.serverError(400, error)
        }

        guard let token = params["token"], !token.isEmpty else {
            throw APIError.serverError(400, "No token in auth callback")
        }

        KeychainHelper.save(token, for: .authToken)

        if let email = params["email"] {
            KeychainHelper.save(email, for: .userEmail)
            userEmail = email
        }

        if let name = params["name"], !name.isEmpty {
            KeychainHelper.save(name, for: .userName)
            userName = name
        }

        isAuthenticated = true
    }
}

private final class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
