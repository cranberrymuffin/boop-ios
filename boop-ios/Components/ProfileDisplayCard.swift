//
//  ProfileDisplayCard.swift
//  boop-ios
//

import SwiftUI

struct ProfileDisplayCard: View {
    let displayName: String
    let birthday: Date?
    let bio: String?
    var avatarData: Data? = nil

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Avatar thumbnail
            if let avatarData, let uiImage = UIImage(data: avatarData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.staticWhite.opacity(0.4), lineWidth: 2))
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.staticWhite.opacity(0.6))
            }

            // Display Name
            Text(displayName)
                .font(.heading1)
                .foregroundColor(.staticWhite)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            
            // Birthday
            if let birthday = birthday {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "birthday.cake")
                        .foregroundColor(.staticWhite)
                    Text(birthday.formatted(.dateTime.month().day()))
                        .font(.subtitle)
                        .foregroundColor(.staticWhite)
                }
            }
            
            // Bio
            if let bio = bio, !bio.isEmpty {
                Text(bio)
                    .foregroundColor(.staticWhite)
                    .multilineTextAlignment(.center)
                    .padding(.top, Spacing.sm)
            }
        }
        .padding(.vertical, Spacing.lg)
    }
}

#Preview {
    ProfileDisplayCard(
        displayName: "Jane Doe",
        birthday: Date(),
        bio: "Coffee enthusiast and part-time adventurer"
    )
    .pageBackground()
}
