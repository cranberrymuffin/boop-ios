//
//  SupabaseClientProvider.swift
//  boop-ios
//
//  Created by GitHub Copilot on 12/24/25.
//

import Foundation
#if canImport(Supabase)
import Supabase
#endif

struct SupabaseConfig {
    // TODO: Set your Supabase URL and anon key
    static let urlString: String = "ASK FOR THIS" // e.g. https://xyzcompany.supabase.co
    static let anonKey: String = "ASK FOR THIS"
}


final class SupabaseClientProvider {
    static let shared = SupabaseClientProvider()

    #if canImport(Supabase)
    let client: SupabaseClient?
    #endif

    private init() {
        #if canImport(Supabase)
        guard let url = URL(string: SupabaseConfig.urlString) else {
            client = nil
            print("⚠️ Invalid Supabase URL")
            return
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
        print("✅ Supabase client initialized")
        #endif
    }
}

#if canImport(Supabase)
extension SupabaseClientProvider {
    func signInWithApple(idToken: String, nonce: String) async throws {
        print("🔵 signInWithApple called")
        guard let client = client else {
            print("⚠️ Supabase client is nil, skipping sign-in")
            return
        }
        print("🔵 Client exists, attempting sign-in with Supabase...")
        try await client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
        )
        print("✅ Supabase signInWithIdToken completed")
    }

    func signOut() async throws {
        guard let client = client else {
            return
        }
        try await client.auth.signOut()
    }
    
    /// Save or update user profile in Supabase
    func upsertProfile(_ profile: SupabaseProfile) async throws {
        guard let client = client else {
            throw SupabaseError.clientNotAvailable
        }
        
        try await client
            .from("profiles")
            .upsert(profile)
            .execute()
        
        print("✅ Profile upserted to Supabase")
    }
    
    /// Fetch user profile from Supabase
    func getProfile(userId: UUID) async throws -> SupabaseProfile {
        guard let client = client else {
            throw SupabaseError.clientNotAvailable
        }
        
        let profile: SupabaseProfile = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId)
            .single()
            .execute()
            .value
        
        return profile
    }
    
    /// Upload avatar image to Supabase Storage
    func uploadAvatar(userId: UUID, imageData: Data) async throws -> String {
        guard let client = client else {
            throw SupabaseError.clientNotAvailable
        }
        
        // Verify we have an authenticated session
        let session = try await client.auth.session
        print("🔍 Upload - Auth User ID: \(session.user.id)")
        print("🔍 Upload - Target User ID: \(userId)")
        print("🔍 Upload - IDs Match: \(session.user.id == userId)")
        
        // Use lowercase UUID to match Supabase's UUID format
        let filePath = "\(userId.uuidString.lowercased())/avatar.jpeg"
        print("🔍 Upload - File Path: \(filePath)")
        
        try await client.storage
            .from("avatars")
            .upload(
                path: filePath,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg", upsert: true)
            )

        // Manually construct the public URL
        let supabaseUrl = SupabaseConfig.urlString
        let publicURL = "\(supabaseUrl)/storage/v1/object/public/avatars/\(filePath)"
        print("✅ Avatar uploaded to Supabase Storage: \(publicURL)")
        return publicURL
    }
    
    /// Download avatar image from Supabase Storage
    func downloadAvatar(path: String) async throws -> Data {
        guard let client = client else {
            throw SupabaseError.clientNotAvailable
        }
        
        let data = try await client.storage
            .from("avatars")
            .download(path: path)
        
        return data
    }
}

enum SupabaseError: Error {
    case clientNotAvailable
    
    var localizedDescription: String {
        switch self {
        case .clientNotAvailable:
            return "Supabase client is not available"
        }
    }
}
#endif
