import Foundation
import Security

enum KeychainSecret {
    private static let service = "dev.acerola.Hourcade"

    private enum Failure: LocalizedError, CustomNSError {
        case update(OSStatus)
        case save(OSStatus)

        static var errorDomain: String { "Hourcade.Keychain" }
        var errorCode: Int {
            switch self {
            case .update(let status), .save(let status): Int(status)
            }
        }
        var errorDescription: String? {
            switch self {
            case .update: L10n.tr("无法更新钥匙串中的密钥")
            case .save: L10n.tr("无法将密钥保存到钥匙串")
            }
        }
        var errorUserInfo: [String: Any] {
            [NSLocalizedDescriptionKey: errorDescription ?? ""]
        }
    }

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard updateStatus == errSecItemNotFound else {
            guard updateStatus == errSecSuccess else {
                throw Failure.update(updateStatus)
            }
            return
        }
        var insert = query
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw Failure.save(status)
        }
    }
}
