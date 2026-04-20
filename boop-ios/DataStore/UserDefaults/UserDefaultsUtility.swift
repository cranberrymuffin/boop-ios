import Foundation

struct UserDefaultsUtility {

    // MARK: - Read Methods

    /// Retrieves a String value from UserDefaults
    /// - Parameter key: The key to retrieve the value for
    /// - Returns: The stored String value, or nil if not found
    static func getString(forKey key: String) async -> String? {
        return UserDefaults.standard.string(forKey: key)
    }

    /// Retrieves a Bool value from UserDefaults
    /// - Parameter key: The key to retrieve the value for
    /// - Returns: The stored Bool value, or false if not found
    static func getBool(forKey key: String) async -> Bool {
        return UserDefaults.standard.bool(forKey: key)
    }

    /// Retrieves a Date value from UserDefaults
    /// - Parameter key: The key to retrieve the value for
    /// - Returns: The stored Date value, or nil if not found
    static func getDate(forKey key: String) async -> Date? {
        return UserDefaults.standard.object(forKey: key) as? Date
    }

    // MARK: - Async Write Methods

    /// Asynchronously stores a String value in UserDefaults
    /// - Parameters:
    ///   - value: The String value to store
    ///   - key: The key to store the value under
    static func setAsync(_ value: String, forKey key: String) async {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Asynchronously stores a Bool value in UserDefaults
    /// - Parameters:
    ///   - value: The Bool value to store
    ///   - key: The key to store the value under
    static func setAsync(_ value: Bool, forKey key: String) async {
        UserDefaults.standard.set(value, forKey: key)
    }

    /// Asynchronously stores a Date value in UserDefaults
    /// - Parameters:
    ///   - value: The Date value to store
    ///   - key: The key to store the value under
    static func setAsync(_ value: Date, forKey key: String) async {
        UserDefaults.standard.set(value, forKey: key)
    }

    // MARK: - Synchronous Write Methods

    /// Synchronously stores a String value in UserDefaults (wraps async in Task)
    /// - Parameters:
    ///   - value: The String value to store
    ///   - key: The key to store the value under
    static func set(_ value: String, forKey key: String) {
        Task {
            await setAsync(value, forKey: key)
        }
    }

    /// Synchronously stores a Bool value in UserDefaults (wraps async in Task)
    /// - Parameters:
    ///   - value: The Bool value to store
    ///   - key: The key to store the value under
    static func set(_ value: Bool, forKey key: String) {
        Task {
            await setAsync(value, forKey: key)
        }
    }

    /// Synchronously stores a Date value in UserDefaults (wraps async in Task)
    /// - Parameters:
    ///   - value: The Date value to store
    ///   - key: The key to store the value under
    static func set(_ value: Date, forKey key: String) {
        Task {
            await setAsync(value, forKey: key)
        }
    }
}
