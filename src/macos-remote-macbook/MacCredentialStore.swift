import Foundation
import Security

struct RememberedMac: Identifiable, Equatable {
    let id: UUID
    let name: String
}

final class MacCredentialStore {
    private let service = "com.jeffhandley.macos-remote.remembered-device"
    private let namesKey = "rememberedMacDeviceNames"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var devices: [RememberedMac] {
        storedNames
            .compactMap { key, name in
                guard let id = UUID(uuidString: key), credential(for: id) != nil else {
                    return nil
                }
                return RememberedMac(id: id, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func credential(for deviceID: UUID) -> String? {
        var query = baseQuery(for: deviceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func matches(_ candidate: String?, for deviceID: UUID) -> Bool {
        guard let candidate, let stored = credential(for: deviceID) else {
            return false
        }
        return timingSafeEqual(candidate, stored)
    }

    func remember(deviceID: UUID, name: String, credential: String) {
        forget(deviceID: deviceID)
        var query = baseQuery(for: deviceID)
        query[kSecValueData as String] = Data(credential.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(query as CFDictionary, nil)

        var names = storedNames
        names[deviceID.uuidString] = name
        defaults.set(names, forKey: namesKey)
    }

    func forget(deviceID: UUID) {
        SecItemDelete(baseQuery(for: deviceID) as CFDictionary)
        var names = storedNames
        names.removeValue(forKey: deviceID.uuidString)
        defaults.set(names, forKey: namesKey)
    }

    private var storedNames: [String: String] {
        defaults.dictionary(forKey: namesKey) as? [String: String] ?? [:]
    }

    private func baseQuery(for deviceID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID.uuidString,
        ]
    }

    private func timingSafeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = [UInt8](lhs.utf8)
        let right = [UInt8](rhs.utf8)
        guard left.count == right.count else {
            return false
        }
        return zip(left, right).reduce(UInt8(0)) { difference, pair in
            difference | (pair.0 ^ pair.1)
        } == 0
    }
}
