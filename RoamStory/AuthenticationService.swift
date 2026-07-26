import AuthenticationServices
import CryptoKit
import FBSDKCoreKit
import FBSDKLoginKit
import Foundation
import GoogleSignIn
import Security
import UIKit

enum LoginProvider: String {
    case google
    case apple
    case facebook
}

struct AccountProfile: Codable, Equatable {
    let id: UUID
    let email: String
    let displayName: String?
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case email = "email"
        case displayName = "displayName"
        case avatarURL = "avatarURL"
    }
}

private struct ServerSession: Codable {
    let user: AccountProfile
    let accountCreated: Bool?
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date

    enum CodingKeys: String, CodingKey {
        case user = "user"
        case accountCreated = "accountCreated"
        case accessToken = "accessToken"
        case refreshToken = "refreshToken"
        case accessExpiresAt = "accessExpiresAt"
        case refreshExpiresAt = "refreshExpiresAt"
    }
}

private struct ExchangeRequest: Encodable {
    let credential: String
    let displayName: String?
    let nonce: String?

    enum CodingKeys: String, CodingKey {
        case credential = "credential"
        case displayName = "displayName"
        case nonce = "nonce"
    }
}

private struct RefreshRequest: Encodable {
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refreshToken"
    }
}

private struct ErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String

        enum CodingKeys: String, CodingKey {
            case code = "code"
            case message = "message"
        }
    }

    let error: Detail

    enum CodingKeys: String, CodingKey {
        case error = "error"
    }
}

enum AuthenticationError: LocalizedError {
    case missingConfiguration(String)
    case invalidCredential
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case let .missingConfiguration(message): message
        case .invalidCredential: "The identity provider did not return a usable credential."
        case .invalidResponse: "The RoamStory server returned an invalid response."
        case let .server(message): message
        }
    }
}

@MainActor
final class AuthenticationStore: ObservableObject {
    @Published private(set) var account: AccountProfile?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published private(set) var activityMessage: String?
    @Published var accountStatusMessage: String?

    private let client: RoamStoryAuthClient
    private let keychain: SessionKeychain
    private var session: ServerSession?
    private var pendingAppleNonce: String?

    init() {
        client = RoamStoryAuthClient()
        keychain = SessionKeychain()
        session = try? keychain.load()
        account = session?.user
    }

    func signInWithGoogle() async {
        await performSignIn {
            let token = try await ProviderLogin.googleIDToken()
            self.activityMessage = "Registering or logging in…"
            return try await self.client.exchange(provider: .google, credential: token)
        }
    }

    func signInWithFacebook() async {
        await performSignIn {
            let token = try await ProviderLogin.facebookAccessToken()
            self.activityMessage = "Registering or logging in…"
            return try await self.client.exchange(provider: .facebook, credential: token)
        }
    }

    func signInWithApple(authorization: ASAuthorization) async {
        await performSignIn {
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                throw AuthenticationError.invalidCredential
            }

            let components = credential.fullName
            let displayName = PersonNameComponentsFormatter()
                .string(from: components ?? PersonNameComponents())
                .nilIfEmpty
            self.activityMessage = "Registering or logging in…"
            return try await self.client.exchange(
                provider: .apple,
                credential: token,
                displayName: displayName,
                nonce: self.pendingAppleNonce
            )
        }
        pendingAppleNonce = nil
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        guard let nonce = Self.randomNonce() else {
            errorMessage = "A secure Apple sign-in request could not be created."
            return
        }
        pendingAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    func handleAppleFailure(_ error: Error) {
        guard (error as? ASAuthorizationError)?.code != .canceled else {
            return
        }
        errorMessage = "Apple sign-in is currently unavailable. Please try again later or use another sign-in method."
    }

    func logout() async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        activityMessage = nil

        if let accessToken = session?.accessToken {
            try? await client.logout(accessToken: accessToken)
        }

        GIDSignIn.sharedInstance.signOut()
        LoginManager().logOut()
        session = nil
        account = nil
        accountStatusMessage = nil
        try? keychain.delete()
        activityMessage = nil
        isWorking = false
    }

    func publish(_ request: PublishTripRequest) async throws -> PublishedTrip {
        let accessToken = try await validAccessToken()
        return try await client.publish(request, accessToken: accessToken)
    }

    func prepareMedia(_ media: LocalPublishMedia) async throws -> PreparedMediaUpload {
        let accessToken = try await validAccessToken()
        return try await client.prepareMedia(media, accessToken: accessToken)
    }

    func uploadMedia(
        _ media: LocalPublishMedia,
        to mediaUuid: UUID
    ) async throws {
        let accessToken = try await validAccessToken()
        try await client.uploadMedia(media, to: mediaUuid, accessToken: accessToken)
    }

    private func validAccessToken() async throws -> String {
        guard let currentSession = session else {
            throw AuthenticationError.server("Sign in to publish this trip.")
        }

        let now = Date()
        if currentSession.accessExpiresAt > now.addingTimeInterval(60) {
            return currentSession.accessToken
        }

        guard currentSession.refreshExpiresAt > now else {
            clearExpiredSession()
            throw AuthenticationError.server(
                "Your RoamStory session has expired. Sign in again."
            )
        }

        do {
            let refreshedSession = try await client.refresh(
                refreshToken: currentSession.refreshToken
            )
            try keychain.save(refreshedSession)
            session = refreshedSession
            account = refreshedSession.user
            return refreshedSession.accessToken
        } catch let error as AuthenticationError {
            if case let .server(message) = error,
               message.localizedCaseInsensitiveContains("refresh token"),
               message.localizedCaseInsensitiveContains("invalid")
                || message.localizedCaseInsensitiveContains("expired") {
                clearExpiredSession()
                throw AuthenticationError.server(
                    "Your RoamStory session has expired. Sign in again."
                )
            }
            throw error
        }
    }

    private func clearExpiredSession() {
        session = nil
        account = nil
        accountStatusMessage = nil
        try? keychain.delete()
    }

    private func performSignIn(_ operation: () async throws -> ServerSession) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        accountStatusMessage = nil
        activityMessage = "Signing in…"

        do {
            let newSession = try await operation()
            try keychain.save(newSession)
            session = newSession
            account = newSession.user
            accountStatusMessage = newSession.accountCreated == true
                ? "Your RoamStory account has been created."
                : nil
        } catch {
            errorMessage = error.localizedDescription
        }

        activityMessage = nil
        isWorking = false
    }

    private static func randomNonce() -> String? {
        let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return nil
        }
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }
}

private struct RoamStoryAuthClient {
    private let baseURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(bundle: Bundle = .main) {
        let configuredURL = bundle.object(forInfoDictionaryKey: "RoamStoryServerBaseURL") as? String
        baseURL = URL(string: configuredURL ?? "https://roamstory.infiz.com")!
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func exchange(
        provider: LoginProvider,
        credential: String,
        displayName: String? = nil,
        nonce: String? = nil
    ) async throws -> ServerSession {
        try await send(
            path: "/api/v1/auth/\(provider.rawValue)/exchange",
            body: ExchangeRequest(credential: credential, displayName: displayName, nonce: nonce)
        )
    }

    func refresh(refreshToken: String) async throws -> ServerSession {
        try await send(
            path: "/api/v1/auth/refresh",
            body: RefreshRequest(refreshToken: refreshToken)
        )
    }

    func logout(accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/auth/logout"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AuthenticationError.invalidResponse
        }
    }

    func publish(
        _ request: PublishTripRequest,
        accessToken: String
    ) async throws -> PublishedTrip {
        try await send(
            path: "/api/v1/trips/publish",
            body: request,
            accessToken: accessToken
        )
    }

    func prepareMedia(
        _ media: LocalPublishMedia,
        accessToken: String
    ) async throws -> PreparedMediaUpload {
        try await send(
            path: "/api/v1/media/uploads",
            body: PrepareMediaUploadRequest(
                sha256: media.sha256,
                byteSize: Int64(media.data.count),
                contentType: media.contentType
            ),
            accessToken: accessToken
        )
    }

    func uploadMedia(
        _ media: LocalPublishMedia,
        to mediaUuid: UUID,
        accessToken: String
    ) async throws {
        var request = URLRequest(
            url: baseURL.appending(path: "/api/v1/media/uploads/\(mediaUuid.uuidString)")
        )
        request.httpMethod = "PUT"
        request.setValue(media.contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = media.data
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error.message)
                ?? Self.fallbackErrorMessage(
                    path: "/api/v1/media/uploads",
                    statusCode: http.statusCode
                )
            throw AuthenticationError.server(message)
        }
    }

    private func send<Request: Encodable, Response: Decodable>(
        path: String,
        body: Request,
        accessToken: String? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error.message)
                ?? Self.fallbackErrorMessage(path: path, statusCode: http.statusCode)
            throw AuthenticationError.server(message)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch let error as DecodingError {
            throw AuthenticationError.server(
                Self.responseDecodingMessage(for: error, path: path)
            )
        }
    }

    private static func responseDecodingMessage(
        for error: DecodingError,
        path: String
    ) -> String {
        #if DEBUG
        print("Unable to decode RoamStory response for \(path): \(error)")
        #endif
        return "RoamStory received an unexpected response. Please try again later."
    }

    private static func fallbackErrorMessage(path: String, statusCode: Int) -> String {
        if statusCode == 413 {
            return "This media file is too large to upload."
        }
        if statusCode == 401 {
            return path.contains("/auth/")
                ? "Sign-in could not be completed. Please try again."
                : "Your RoamStory session has expired. Sign in again."
        }
        if statusCode >= 500 {
            return "RoamStory is temporarily unavailable. Please try again later."
        }
        if path.contains("/media/") {
            return "The media request could not be completed. Please try again."
        }
        if path.contains("/trips/") {
            return "The trip could not be published. Please try again."
        }
        return "The request could not be completed. Please try again."
    }
}

private enum ProviderLogin {
    @MainActor
    static func googleIDToken() async throws -> String {
        let clientID = try configuredValue("GIDClientID", provider: "Google")
        let serverClientID = try configuredValue("GIDServerClientID", provider: "Google")
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: clientID,
            serverClientID: serverClientID
        )
        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: try presentingViewController()
        )
        guard let token = result.user.idToken?.tokenString else {
            throw AuthenticationError.invalidCredential
        }
        return token
    }

    @MainActor
    static func facebookAccessToken() async throws -> String {
        _ = try configuredValue("FacebookAppID", provider: "Facebook")
        _ = try configuredValue("FacebookClientToken", provider: "Facebook")
        let manager = LoginManager()
        let presenter = try presentingViewController()
        let result = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<LoginManagerLoginResult, Error>) in
            manager.logIn(
                permissions: ["public_profile", "email"],
                from: presenter
            ) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: AuthenticationError.invalidCredential)
                }
            }
        }
        guard !result.isCancelled, let token = AccessToken.current?.tokenString else {
            throw AuthenticationError.invalidCredential
        }
        return token
    }

    @MainActor
    private static func presentingViewController() throws -> UIViewController {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
            let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            throw AuthenticationError.invalidResponse
        }

        var presenter = root
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        return presenter
    }

    private static func configuredValue(_ key: String, provider: String) throws -> String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.isEmpty,
            !value.contains("$("),
            !value.hasPrefix("replace-")
        else {
            throw AuthenticationError.missingConfiguration(
                "\(provider) sign-in is currently unavailable. Please try another sign-in method."
            )
        }
        return value
    }
}

private struct SessionKeychain {
    private let service = "com.infiz.roamstory.authentication"
    private let account = "server-session"

    func save(_ session: ServerSession) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AuthenticationError.server("The login could not be saved securely.")
        }
    }

    func load() throws -> ServerSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AuthenticationError.server("The saved login could not be read.")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ServerSession.self, from: data)
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthenticationError.server("The saved login could not be removed.")
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
