import Foundation
import SwiftUI

/// Unified data store providing a single interface for accessing user data
/// Internally uses UserDefaults for persistence with optional in-memory caching
actor UserDataStore {
    static let shared = UserDataStore()

    // In-memory cache for frequently accessed values
    private var cache: [String: Any] = [:]
    private var isWarmedUp = false

    private init() {}

    // MARK: - Warmup

    /// Loads frequently accessed data from UserDefaults into memory cache
    /// Should be called during app initialization
    func warmup() async {
        guard !isWarmedUp else { return }

        // Wait for storage initialization to complete before accessing UserDefaults
        try? await StorageCoordinator.shared.waitForInitialization()

        // Pre-load user profile data into cache
        if let name = UserDefaults.standard.string(forKey: UserDefaultsKeys.name) {
            cache[UserDefaultsKeys.name] = name
        }

        if let birthday = UserDefaults.standard.object(forKey: UserDefaultsKeys.birthday) as? Date {
            cache[UserDefaultsKeys.birthday] = birthday
        }

        if let bio = UserDefaults.standard.string(forKey: UserDefaultsKeys.bio) {
            cache[UserDefaultsKeys.bio] = bio
        }
        
        if let gradientColors = UserDefaults.standard.array(forKey: UserDefaultsKeys.gradientColors) as? [String] {
            cache[UserDefaultsKeys.gradientColors] = gradientColors
        }

        cache[UserDefaultsKeys.profileComplete] = UserDefaults.standard.bool(forKey: UserDefaultsKeys.profileComplete)

        isWarmedUp = true
    }

    // MARK: - User Profile Accessors

    /// Returns the user's name if available
    func getName() async -> String? {
        if let cached = cache[UserDefaultsKeys.name] as? String {
            return cached
        }
        return UserDefaults.standard.string(forKey: UserDefaultsKeys.name)
    }

    /// Returns the user's birthday if available
    func getBirthday() async -> Date? {
        if let cached = cache[UserDefaultsKeys.birthday] as? Date {
            return cached
        }
        return UserDefaults.standard.object(forKey: UserDefaultsKeys.birthday) as? Date
    }

    /// Returns the user's bio if available
    func getBio() async -> String? {
        if let cached = cache[UserDefaultsKeys.bio] as? String {
            return cached
        }
        return UserDefaults.standard.string(forKey: UserDefaultsKeys.bio)
    }
    
    /// Returns the user's avatar image data if available
    func getAvatarData() async -> Data? {
        return nil
    }

    /// Returns the user's gradient colors if available
    func getGradientColors() async -> [String]? {
        if let cached = cache[UserDefaultsKeys.gradientColors] as? [String] {
            return cached
        }
        return UserDefaults.standard.array(forKey: UserDefaultsKeys.gradientColors) as? [String]
    }
    
    /// Returns whether the user's profile setup is complete
    func isProfileComplete() async -> Bool {
        if let cached = cache[UserDefaultsKeys.profileComplete] as? Bool {
            return cached
        }
        return UserDefaults.standard.bool(forKey: UserDefaultsKeys.profileComplete)
    }

    // MARK: - Bulk Profile Operations

    /// Returns all available user profile data
    /// Returns nil if no profile exists
    func getUserProfile() async -> UserProfileData? {
        print("Get UserProfile called")

        guard let name = await getName() else {
            print("No profile found")
            return nil
        }

        let birthday = await getBirthday()
        let bio = await getBio()
        let gradientColors = await getGradientColors() ?? []
        let avatarData = await getAvatarData()
        let userProfileData = UserProfileData(
            name: name,
            birthday: birthday,
            bio: bio,
            gradientColorsData: gradientColors,
            avatarData: avatarData
        )
        print("Constructed user profile data. Display Name: \(userProfileData.displayName)")
        return userProfileData
    }

    /// Saves user profile data to storage
    /// Updates both cache and UserDefaults
    func setUserProfile(_ profile: UserProfile) async {
        // Update UserDefaults
        UserDefaults.standard.set(profile.name, forKey: UserDefaultsKeys.name)
        if let birthday = profile.birthday {
            UserDefaults.standard.set(birthday, forKey: UserDefaultsKeys.birthday)
        }
        if let bio = profile.bio {
            UserDefaults.standard.set(bio, forKey: UserDefaultsKeys.bio)
        }
        UserDefaults.standard.set(profile.gradientColorsData, forKey: UserDefaultsKeys.gradientColors)

        // Update cache
        cache[UserDefaultsKeys.name] = profile.name
        if let birthday = profile.birthday {
            cache[UserDefaultsKeys.birthday] = birthday
        }
        if let bio = profile.bio {
            cache[UserDefaultsKeys.bio] = bio
        }
        cache[UserDefaultsKeys.gradientColors] = profile.gradientColorsData
    }

    // MARK: - Individual Setters

    /// Sets the profile completion status
    func setProfileComplete(_ isComplete: Bool) async {
        UserDefaults.standard.set(isComplete, forKey: UserDefaultsKeys.profileComplete)
        cache[UserDefaultsKeys.profileComplete] = isComplete
    }

    // MARK: - Cache Management

    /// Clears all user data from both cache and UserDefaults
    /// Use this when logging out
    func clear() async {
        // Clear cache
        cache.removeAll()

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.name)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.birthday)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.bio)
        UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.profileComplete)

        isWarmedUp = false
    }
}

// MARK: - Data Transfer Object

/// Simple data structure representing user profile data from the store
/// Use this when you need to read multiple profile fields at once
struct UserProfileData {
    let name: String
    let birthday: Date?
    let bio: String?
    let gradientColorsData: [String]
    let avatarData: Data?

    init(name: String, birthday: Date?, bio: String?, gradientColorsData: [String], avatarData: Data? = nil) {
        self.name = name
        self.birthday = birthday
        self.bio = bio
        self.gradientColorsData = gradientColorsData
        self.avatarData = avatarData
    }

    var displayName: String {
        "\(name)"
    }
    
    var gradientColors: [Color] {
        gradientColorsData.compactMap { colorString in
            switch colorString {
            case "red": return .red
            case "orange": return .orange
            case "yellow": return .yellow
            case "green": return .green
            case "cyan": return .cyan
            case "blue": return .blue
            case "indigo": return .indigo
            case "purple": return .purple
            case "pink": return .pink
            case "mint": return .mint
            case "teal": return .teal
            case "brown": return .brown
            case "white": return .white
            case "black": return .black
            case "gray": return .gray
            default: return nil
            }
        }
    }
}
