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

private struct UpdateProfileRequest: Encodable {
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case displayName = "displayName"
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
    @Published private(set) var shouldPromptForNickname = false

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
            let credential = try await ProviderLogin.facebookCredential()
            self.activityMessage = "Registering or logging in…"
            return try await self.client.exchange(
                provider: .facebook,
                credential: credential.token,
                nonce: credential.nonce
            )
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

        if let currentSession = session {
            try? await client.logout(
                accessToken: currentSession.accessToken,
                refreshToken: currentSession.refreshToken
            )
        }

        GIDSignIn.sharedInstance.signOut()
        LoginManager().logOut()
        session = nil
        account = nil
        shouldPromptForNickname = false
        try? keychain.delete()
        activityMessage = nil
        isWorking = false
    }

    func dismissNicknamePrompt() {
        shouldPromptForNickname = false
    }

    func updateNickname(_ nickname: String) async {
        guard !isWorking else { return }
        let nickname = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nickname.isEmpty else {
            errorMessage = "Enter a nickname before saving."
            return
        }
        guard nickname.count <= 50 else {
            errorMessage = "Nickname must be 50 characters or fewer."
            return
        }

        isWorking = true
        errorMessage = nil
        activityMessage = "Saving nickname…"
        do {
            let accessToken = try await validAccessToken()
            let updatedAccount = try await client.updateProfile(
                displayName: nickname,
                accessToken: accessToken
            )
            try replaceAccount(updatedAccount)
            shouldPromptForNickname = false
        } catch {
            errorMessage = error.localizedDescription
        }
        activityMessage = nil
        isWorking = false
    }

    func publish(_ request: PublishTripRequest) async throws -> PublishedTrip {
        let accessToken = try await validAccessToken()
        return try await client.publish(request, accessToken: accessToken)
    }

    func publishedTripLikes(
        publicURL: URL,
        tripUuid: UUID
    ) async throws -> PublishedTripLikeSummary {
        let accessToken: String?
        if session == nil {
            accessToken = nil
        } else {
            accessToken = try await validAccessToken()
        }
        let pathComponents = publicURL.pathComponents.filter { $0 != "/" }
        guard let sharesIndex = pathComponents.firstIndex(of: "shares"),
              pathComponents.indices.contains(sharesIndex + 1)
        else {
            throw AuthenticationError.invalidResponse
        }
        let response = try await client.likes(
            slug: pathComponents[sharesIndex + 1],
            accessToken: accessToken
        )
        guard let tripLike = response.likes.first(where: {
            $0.targetType == "trip" && $0.targetUuid == tripUuid
        }) else {
            return PublishedTripLikeSummary(count: 0, recentLikers: [])
        }
        return PublishedTripLikeSummary(
            count: tripLike.count,
            recentLikers: Array(tripLike.recentLikers.prefix(5))
        )
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
        shouldPromptForNickname = false
        try? keychain.delete()
    }

    private func replaceAccount(_ updatedAccount: AccountProfile) throws {
        guard let currentSession = session else {
            throw AuthenticationError.server("Sign in again to update your nickname.")
        }
        let updatedSession = ServerSession(
            user: updatedAccount,
            accountCreated: currentSession.accountCreated,
            accessToken: currentSession.accessToken,
            refreshToken: currentSession.refreshToken,
            accessExpiresAt: currentSession.accessExpiresAt,
            refreshExpiresAt: currentSession.refreshExpiresAt
        )
        try keychain.save(updatedSession)
        session = updatedSession
        account = updatedAccount
    }

    private func performSignIn(_ operation: () async throws -> ServerSession) async {
        guard !isWorking else { return }
        isWorking = true
        errorMessage = nil
        activityMessage = "Signing in…"

        do {
            let newSession = try await operation()
            try keychain.save(newSession)
            session = newSession
            account = newSession.user
            shouldPromptForNickname = newSession.accountCreated == true
        } catch {
            errorMessage = error.localizedDescription
        }

        activityMessage = nil
        isWorking = false
    }

    fileprivate static func randomNonce() -> String? {
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
            path: "/api/v1/auth/ios/\(provider.rawValue)/exchange",
            body: ExchangeRequest(credential: credential, displayName: displayName, nonce: nonce)
        )
    }

    func refresh(refreshToken: String) async throws -> ServerSession {
        try await send(
            path: "/api/v1/auth/ios/refresh",
            body: RefreshRequest(refreshToken: refreshToken)
        )
    }

    func logout(accessToken: String, refreshToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/auth/ios/logout"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(RefreshRequest(refreshToken: refreshToken))
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw AuthenticationError.invalidResponse
        }
    }

    func updateProfile(
        displayName: String,
        accessToken: String
    ) async throws -> AccountProfile {
        var request = URLRequest(url: baseURL.appending(path: "/api/v1/me"))
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try encoder.encode(UpdateProfileRequest(displayName: displayName))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthenticationError.invalidResponse
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error.message)
                ?? Self.fallbackErrorMessage(path: "/api/v1/me", statusCode: http.statusCode)
            throw AuthenticationError.server(message)
        }
        do {
            return try decoder.decode(AccountProfile.self, from: data)
        } catch let error as DecodingError {
            throw AuthenticationError.server(
                Self.responseDecodingMessage(for: error, path: "/api/v1/me")
            )
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

    func likes(
        slug: String,
        accessToken: String?
    ) async throws -> PublishedLikesResponse {
        let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? slug
        let path = "/api/v1/shares/\(encodedSlug)/likes"
        var request = URLRequest(url: baseURL.appending(path: path))
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
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
            return try decoder.decode(PublishedLikesResponse.self, from: data)
        } catch let error as DecodingError {
            throw AuthenticationError.server(
                Self.responseDecodingMessage(for: error, path: path)
            )
        }
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
    struct FacebookCredential {
        let token: String
        let nonce: String
    }

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
    static func facebookCredential() async throws -> FacebookCredential {
        _ = try configuredValue("FacebookAppID", provider: "Facebook")
        _ = try configuredValue("FacebookClientToken", provider: "Facebook")
        let manager = LoginManager()
        let presenter = try presentingViewController()
        guard let nonce = AuthenticationStore.randomNonce() else {
            throw AuthenticationError.invalidCredential
        }
        guard let configuration = LoginConfiguration(
            permissions: ["public_profile", "email"],
            tracking: .limited,
            nonce: nonce
        ) else {
            throw AuthenticationError.invalidCredential
        }
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            manager.logIn(viewController: presenter, configuration: configuration) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: AuthenticationError.invalidCredential)
                case let .failed(error):
                    continuation.resume(throwing: error)
                }
            }
        }
        guard
            let authenticationToken = AuthenticationToken.current,
            authenticationToken.nonce == nonce
        else {
            throw AuthenticationError.invalidCredential
        }
        return FacebookCredential(token: authenticationToken.tokenString, nonce: nonce)
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
