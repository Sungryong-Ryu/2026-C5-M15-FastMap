import AuthenticationServices
import Combine
import Foundation
import Security

struct AppleAccount: Codable, Equatable {
    let userIdentifier: String
    var displayName: String
    var email: String?
}

@MainActor
final class AccountManager: ObservableObject {
    @Published private(set) var account: AppleAccount?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isCheckingCredential = false

    var isSignedIn: Bool { account != nil }

    init() {
        account = Self.loadAccount()
    }

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func complete(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple 로그인 정보를 확인하지 못했습니다."
                return
            }

            let previousAccount = account
            let providedName = credential.fullName.map {
                PersonNameComponentsFormatter().string(from: $0)
            }
            let displayName = providedName?.isEmpty == false
                ? providedName!
                : previousAccount?.displayName ?? "FastMap 사용자"

            let signedInAccount = AppleAccount(
                userIdentifier: credential.user,
                displayName: displayName,
                email: credential.email ?? previousAccount?.email
            )
            account = signedInAccount
            errorMessage = nil
            Self.saveAccount(signedInAccount)

        case .failure(let error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            errorMessage = "Apple 로그인에 실패했습니다. 잠시 후 다시 시도해주세요."
        }
    }

    func validateCredential() async {
        guard let account else { return }
        isCheckingCredential = true
        defer { isCheckingCredential = false }

        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: account.userIdentifier)
            if state == .revoked || state == .notFound {
                signOut()
            }
        } catch {
            // Keep the cached session while offline. Apple validates it again next launch.
        }
    }

    func signOut() {
        account = nil
        errorMessage = nil
        Self.deleteAccount()
    }

    private static let service = "com.hwagodong.FastMap.apple-account"
    private static let accountKey = "current-account"

    private static func saveAccount(_ account: AppleAccount) {
        guard let data = try? JSONEncoder().encode(account) else { return }
        deleteAccount()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadAccount() -> AppleAccount? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AppleAccount.self, from: data)
    }

    private static func deleteAccount() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
