# Supabase Integration Guide

## Overview

This app integrates with Supabase for backend services including:

- **Authentication**: Sign in with Apple via Supabase Auth
- **Profile Storage**: User profiles in PostgreSQL
- **Photo Storage**: Avatar uploads to Supabase Storage

The integration follows the [official Supabase Swift tutorial](https://supabase.com/docs/guides/getting-started/tutorials/with-swift).

## Setup

### 1. Create Database Schema

Run this SQL in your Supabase SQL Editor to create the required tables and policies:

```sql
-- Create profiles table
CREATE TABLE profiles (
  id UUID REFERENCES auth.users PRIMARY KEY,
  first_name TEXT,
  last_name TEXT,
  date_of_birth DATE,
  avatar_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable Row Level Security
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Create policies for profiles table
CREATE POLICY "Users can view their own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Users can insert their own profile"
  ON profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Create avatars table to track avatar metadata with user association
CREATE TABLE avatars (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users ON DELETE CASCADE,
  storage_path TEXT NOT NULL UNIQUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- Enable Row Level Security
ALTER TABLE avatars ENABLE ROW LEVEL SECURITY;

-- Create policies for avatars table
CREATE POLICY "Users can view their own avatars"
  ON avatars FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can insert their own avatars"
  ON avatars FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own avatars"
  ON avatars FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own avatars"
  ON avatars FOR DELETE
  USING (auth.uid() = user_id);

-- Create index on user_id for faster lookups
CREATE INDEX avatars_user_id_idx ON avatars(user_id);

-- Create avatars storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true);

-- Storage policies for avatar uploads
CREATE POLICY "Users can upload their own avatar"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'avatars' AND
    auth.uid()::text = (string_to_array(name, '/'))[1]
  );

CREATE POLICY "Users can update their own avatar"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'avatars' AND
    auth.uid()::text = (string_to_array(name, '/'))[1]
  );

CREATE POLICY "Users can delete their own avatar"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'avatars' AND
    auth.uid()::text = (string_to_array(name, '/'))[1]
  );

CREATE POLICY "Public avatars are accessible to all"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'avatars');
```

### 2. Configure Supabase Credentials

Update `SupabaseClientProvider.swift` with your credentials:

```swift
struct SupabaseConfig {
    static let urlString: String = "YOUR_SUPABASE_URL"
    static let anonKey: String = "YOUR_SUPABASE_ANON_KEY"
}
```

Get these values from your [Supabase Dashboard](https://supabase.com/dashboard/project/_/settings/api).

### 3. Configure Deep Links

Add the redirect URL to Supabase Dashboard → Authentication → URL Configuration:

- Add `io.supabase.boop-ios://login-callback` to Redirect URLs

Verify the URL scheme is in `Info.plist` and Apple Sign In capability is enabled in Xcode.

## Architecture

### Data Models

#### `SupabaseProfile`

Codable struct that maps to the Supabase `profiles` table:

- `id`: UUID (matches auth.users.id)
- `firstName`: User's first name
- `lastName`: User's last name
- `dateOfBirth`: Date of birth (ISO 8601 string)
- `avatarURL`: Path to avatar image in Storage
- `createdAt`: Timestamp

```swift
init(id: UUID?, firstName: String?, lastName: String?, dateOfBirth: Date?, avatarURL: String? = nil)
```

Automatically converts `Date` to ISO 8601 string for Supabase compatibility.

#### `UserProfile` (SwiftData)

Local-first persistence model stored in SwiftData:

- `appleUserID`: Apple user identifier
- `firstName`, `lastName`: User's name components
- `dateOfBirth`: Date of birth
- `createdAt`: Timestamp
- `displayName`: Computed property combining first + last name

#### `AvatarImage`

Transferable type for PhotosPicker integration:

- `image`: SwiftUI Image for preview display
- `data`: Raw Data for upload to Storage
- Conforms to `Transferable` protocol

### Data Flow

```
┌─────────────────────┐
│  Sign in with Apple │
└──────────┬──────────┘
           ↓
┌──────────────────────────┐
│  ProfileSetupView        │
│  - Enter first/last name │
│  - Select photo (opt.)   │
│  - Set date of birth     │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│  Upload avatar to        │
│  Supabase Storage        │
│  (avatars/uuid/avatar.jpeg)│
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│  Save profile to         │
│  Supabase (profiles tbl) │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│  Save profile locally    │
│  to SwiftData            │
└──────────┬───────────────┘
           ↓
┌──────────────────────────┐
│  Auth state: .completed  │
└──────────────────────────┘
```

## API Reference

### `SupabaseClientProvider`

```swift
// Sign in with Apple ID token
func signInWithApple(idToken: String, nonce: String) async throws

// Sign out
func signOut() async throws

// Save or update profile
func upsertProfile(_ profile: SupabaseProfile) async throws

// Fetch profile by user ID
func getProfile(userId: UUID) async throws -> SupabaseProfile

// Upload avatar image to Storage
func uploadAvatar(userId: UUID, imageData: Data) async throws -> String

// Download avatar image from Storage
func downloadAvatar(path: String) async throws -> Data

// Delete avatar from Storage and metadata table
func deleteAvatar(path: String) async throws
```

All operations are wrapped in `#if canImport(Supabase)` for graceful degradation.

## Usage Examples

### Creating a Profile with Photo

```swift
// 1. Upload photo to Supabase Storage
let avatarURL = try await SupabaseClientProvider.shared.uploadAvatar(
    userId: currentUser.id,
    imageData: photoData
)

// 2. Create profile with avatar
let profile = SupabaseProfile(
    id: currentUser.id,
    firstName: "John",
    lastName: "Doe",
    dateOfBirth: Date(),
    avatarURL: avatarURL
)

// 3. Save to Supabase
try await SupabaseClientProvider.shared.upsertProfile(profile)
```

### Fetching a Profile

```swift
let userId = UUID(uuidString: "...")!
let profile = try await SupabaseClientProvider.shared.getProfile(userId: userId)
let fullName = "\(profile.firstName ?? "") \(profile.lastName ?? "")".trimmingCharacters(in: .whitespaces)
print("Full Name: \(fullName)")
```

### Downloading an Avatar

```swift
let avatarData = try await SupabaseClientProvider.shared.downloadAvatar(
    path: "user-id/avatar.jpeg"
)
let image = UIImage(data: avatarData)
```

## Schema Design Notes

### Name Fields: `first_name` and `last_name`

Split into separate columns for better query and validation capabilities:

- Query users by first or last name
- Validate name components independently
- Flexible for international name formats

### Avatar Storage

- **Table**: `avatars` tracks metadata with user association
- **Bucket**: `avatars` (public)
- **File naming**: `{user-id}/{unique-uuid}.jpeg` (each upload gets unique UUID)
- **Access**: Public read (anyone can view avatars in Storage)
- **Upload**: User can only upload their own (enforced by RLS on both table and Storage)
- **Metadata**: Each upload creates entry in `avatars` table with `user_id` and `storage_path`

### Security with RLS

- Users can only view/update their own profile
- Row Level Security enforced at database level
- Safe to use anon key in client (RLS prevents unauthorized access)

## Changes Made

### Removed Username Field

The username field has been removed from the profile system. Users are identified by:

- **Unique ID**: Supabase Auth UUID (immutable)
- **Display Name**: `{firstName} {lastName}` (shown in UI)

The username was redundant since auth UUID provides unique identification.

### New Features

#### Photo Upload Integration

- PhotosPicker UI in ProfileSetupView
- Circular avatar preview (80x80)
- Automatic upload to Supabase Storage
- Graceful error handling (profile saves even if photo fails)

#### Database-Backed Profiles

- All user profiles synced to Supabase
- Local-first (SwiftData) with remote backup
- Async/await based operations
- Comprehensive error handling

## Error Handling

```swift
enum SupabaseError: Error {
    case clientNotAvailable
    case authenticationFailed
    case profileNotFound
    case uploadFailed
}
```

All errors from Supabase operations are properly propagated with user-friendly messages.

## Troubleshooting

### "Supabase client not available"

- Verify the Supabase package is added to Xcode project
- Check `SupabaseConfig` has valid URL and anon key
- Ensure `#if canImport(Supabase)` blocks are in place

### "User not found" on profile fetch

- User must be authenticated before fetching profile
- Verify profile was created during setup
- Check Row Level Security policies allow access

### Sign in with Apple fails

- Verify redirect URL in Supabase Dashboard matches `Info.plist`
- Check Apple Sign In capability is enabled in Xcode
- Confirm URL scheme `io.supabase.boop-ios://` is registered

### Avatar upload fails but profile saves

- This is expected behavior (graceful error handling)
- Check Storage bucket policies allow user uploads
- Verify bucket name is 'avatars'

## Testing

- [x] Profile creation with separate first/last name
- [x] Photo upload to Supabase Storage
- [x] Profile sync to Supabase database
- [x] Graceful degradation without Supabase package
- [x] Proper error messages to user
- [x] Profile editing with avatar updates
- [x] Avatar deletion from Storage on replacement
- [x] Tab navigation (Timeline + You)

## Next Steps

- [ ] Add real-time subscriptions for profile updates
- [ ] Sync boop interactions to Supabase
- [ ] Add social features (friends, contacts)
- [ ] Add image compression before upload
- [ ] Support avatar deletion UI (delete button in You tab)

## Resources

- [Supabase Swift Docs](https://supabase.com/docs/reference/swift)
- [Supabase Auth Guide](https://supabase.com/docs/guides/auth)
- [Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [Tutorial: User Management with Swift](https://supabase.com/docs/guides/getting-started/tutorials/with-swift)
- [Supabase Storage Guide](https://supabase.com/docs/guides/storage)
