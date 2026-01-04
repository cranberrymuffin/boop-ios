//
//  SupabaseProfile.swift
//  boop-ios
//
//

import Foundation

/// Model for Supabase profiles table
/// Matches the schema created by the "User Management Starter" quickstart
struct SupabaseProfile: Codable {
    let id: UUID?
    let firstName: String?
    let lastName: String?
    let dateOfBirth: String?  // ISO 8601 date string
    let avatarURL: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName = "last_name"
        case dateOfBirth = "date_of_birth"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
    
    init(id: UUID?, firstName: String?, lastName: String?, dateOfBirth: Date?, avatarURL: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.avatarURL = avatarURL
        
        // Convert Date to ISO 8601 string for Supabase
        if let dob = dateOfBirth {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            self.dateOfBirth = formatter.string(from: dob)
        } else {
            self.dateOfBirth = nil
        }
        
        self.createdAt = nil  // Let Supabase set this
    }
}
