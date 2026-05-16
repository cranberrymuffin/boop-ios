//
//  ViewModifiers+DesignSystem.swift
//  boop-ios
//
//  Custom ViewModifiers for consistent design system application
//  References generated design tokens from Colors, Typography, Spacing, Sizes, and Radius
//

import SwiftUI

// MARK: - Typography Modifiers

/// Primary text style: SF Pro Bold 32pt with primary text color
/// Used for main page headers
struct PrimaryTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.primary)
            .foregroundColor(.textPrimary)
            .lineSpacing(for: .primary)
    }
}

/// Heading 1 style: SF Pro Semibold 28pt with primary text color
/// Used for section headers
struct Heading1Style: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.heading1)
            .background(Color.clear)
            .foregroundColor(.textMuted)
            .lineSpacing(for: .heading1)
    }
}

/// Heading 2 style: SF Pro Semibold 24pt with secondary text color
/// Used for card titles and subsection headers
struct Heading2Style: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.heading2)
            .foregroundColor(.textSecondary)
            .lineSpacing(for: .heading2)
    }
}

/// Heading 3 style: SF Pro Semibold 20pt with secondary text color
/// Used for card detail subtitle
struct Heading3Style: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.heading3)
            .foregroundColor(.textMuted)
            .lineSpacing(for: .heading3)
    }
}

/// Subtitle style: SF Pro Regular 14pt with muted text color
/// Used for captions, metadata, and secondary information
struct SubtitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subtitle)
            .foregroundColor(.textMuted)
            .lineSpacing(for: .subtitle)
    }
}

/// Error text style: Subtitle font with error color
/// Used for error messages and validation feedback
struct ErrorTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subtitle)
            .foregroundColor(.statusError)
            .lineSpacing(for: .subtitle)
    }
}

/// Success text style: Subtitle font with success color
/// Used for success messages and positive feedback
struct SuccessTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.subtitle)
            .foregroundColor(.statusSuccess)
            .lineSpacing(for: .subtitle)
    }
}

// MARK: - Container Modifiers

/// Card style: Secondary background with medium corner radius
/// Used for cards, panels, and elevated content
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.backgroundSecondary)
            .cornerRadius(CornerRadius.md)
    }
}

/// Page background: Primary background that ignores safe area
/// Used for full-screen backgrounds on main views
struct PageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Color.backgroundPrimary
            )
    }
}

/// Section container: Consistent padding for content sections
/// Used for grouping related content with standard spacing
struct SectionContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
    }
}

// MARK: - Interactive Modifiers

/// Icon button style: Circular background with standard sizing
/// Used for icon-only buttons (back, close, action buttons)
struct IconButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: ComponentSize.buttonSize, height: ComponentSize.buttonSize)
            .background(Color.white.opacity(0.9))
            .clipShape(Circle())
    }
}

/// Primary button style: Standard button appearance with accent color
/// Used for primary action buttons
struct PrimaryButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.heading2)
            .foregroundColor(.textOnAccent)
            .frame(height: ComponentSize.buttonSize)
            .frame(maxWidth: .infinity)
            .background(Color.accentPrimary)
            .cornerRadius(CornerRadius.lg)
    }
}

// MARK: - View Extensions

extension View {
    // Typography
    func primaryTextStyle() -> some View {
        modifier(PrimaryTextStyle())
    }

    func heading1Style() -> some View {
        modifier(Heading1Style())
    }

    func heading2Style() -> some View {
        modifier(Heading2Style())
    }
    
    func heading3Style() -> some View {
        modifier(Heading3Style())
    }

    func subtitleStyle() -> some View {
        modifier(SubtitleStyle())
    }

    func errorTextStyle() -> some View {
        modifier(ErrorTextStyle())
    }

    func successTextStyle() -> some View {
        modifier(SuccessTextStyle())
    }

    // Containers
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    func pageBackground() -> some View {
        modifier(PageBackground())
    }

    func sectionContainer() -> some View {
        modifier(SectionContainer())
    }

    // Interactive
    func iconButtonStyle() -> some View {
        modifier(IconButtonStyle())
    }

    func primaryButtonStyle() -> some View {
        modifier(PrimaryButtonStyle())
    }
}
