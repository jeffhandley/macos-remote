import Foundation
import Security

struct KnownMac: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
}

final class IOSDeviceStore {
    private let defaults: UserDefaults
    private let devicesKey = "knownMacs"
    private let clientIDKey = "clientDeviceID"
    private let credentialService = "com.jeffhandley.macos-remote.mac-credential"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var clientID: UUID {
        if let value = defaults.string(forKey: clientIDKey),
           let identifier = UUID(uuidString: value) {
            return identifier
        }
        let identifier = UUID()
        defaults.set(identifier.uuidString, forKey: clientIDKey)
        return identifier
    }

    var devices: [KnownMac] {
        guard let data = defaults.data(forKey: devicesKey),
              let devices = try? JSONDecoder().decode([KnownMac].self, from: data)
        else {
            return []
        }
        return devices.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func remember(_ device: KnownMac, credential: String?) {
        var current = devices.filter { $0.id != device.id }
        current.append(device)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: devicesKey)
        }

        if let credential {
            setCredential(credential, for: device.id)
        } else {
            removeCredential(for: device.id)
        }
    }

    func update(_ device: KnownMac) {
        var current = devices.filter { $0.id != device.id }
        current.append(device)
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: devicesKey)
        }
    }

    func credential(for peripheralID: UUID) -> String? {
        var query = credentialQuery(for: peripheralID)
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

    func forget(_ device: KnownMac) {
        let remaining = devices.filter { $0.id != device.id }
        if let data = try? JSONEncoder().encode(remaining) {
            defaults.set(data, forKey: devicesKey)
        }
        removeCredential(for: device.id)
    }

    func removeCredential(for peripheralID: UUID) {
        SecItemDelete(credentialQuery(for: peripheralID) as CFDictionary)
    }

    private func setCredential(_ credential: String, for peripheralID: UUID) {
        removeCredential(for: peripheralID)
        var query = credentialQuery(for: peripheralID)
        query[kSecValueData as String] = Data(credential.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func credentialQuery(for peripheralID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: credentialService,
            kSecAttrAccount as String: peripheralID.uuidString,
        ]
    }
}
