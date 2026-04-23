import Foundation
import Security
import os

/// Securely stores and retrieves API keys using Keychain with iCloud sync.
/// For local (unsigned) builds, uses UserDefaults instead since Keychain
/// requires stable code signing to reliably persist data across rebuilds.
final class KeychainService {
    static let shared = KeychainService()

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "KeychainService")
    private let service = "com.prakashjoshipax.VoiceInk"

    private let defaults = UserDefaults.standard
    private let localPrefix = "LocalKeychain_"

    private init() {}

    // MARK: - Public API

    /// Saves a string value to Keychain.
    @discardableResult
    func save(_ value: String, forKey key: String, syncable: Bool = true) -> Bool {
        guard let data = value.data(using: .utf8) else {
            logger.error("Failed to convert value to data for key: \(key, privacy: .public)")
            return false
        }
        return save(data: data, forKey: key, syncable: syncable)
    }

    /// Saves data to Keychain.
    @discardableResult
    func save(data: Data, forKey key: String, syncable: Bool = true) -> Bool {
        defaults.set(data, forKey: localPrefix + key)
        return true
    }

    /// Retrieves a string value from Keychain.
    func getString(forKey key: String, syncable: Bool = true) -> String? {
        guard let data = getData(forKey: key, syncable: syncable) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Retrieves data from Keychain.
    func getData(forKey key: String, syncable: Bool = true) -> Data? {
        return defaults.data(forKey: localPrefix + key)
    }

    /// Deletes an item from Keychain.
    @discardableResult
    func delete(forKey key: String, syncable: Bool = true) -> Bool {
        defaults.removeObject(forKey: localPrefix + key)
        return true
    }

    /// Checks if a key exists in Keychain.
    func exists(forKey key: String, syncable: Bool = true) -> Bool {
        return defaults.data(forKey: localPrefix + key) != nil
    }
}
