//
//  Typography+DesignSystem.swift
//  boop-ios
//
//  Generated from design-tokens/typography.json
//

import SwiftUI

extension Font {
    // MARK: - Typography Styles

    /// Primary font style: SF Pro Bold, 32pt
    /// Used for main page headers
    static let primary = Font.system(size: 32, weight: .bold)
        .leading(.init(1.1))

    /// Subtitle font style: SF Pro Regular, 14pt
    /// Used for secondary text and captions
    static let subtitle = Font.system(size: 14, weight: .regular)
        .leading(.init(20))

    /// Heading 1 font style: SF Pro Semibold, 28pt
    /// Used for section headers
    static let heading1 = Font.system(size: 28, weight: .semibold)
        .leading(.init(1.13))

    /// Heading 2 font style: SF Pro Semibold, 24pt
    /// Used for card titles
    static let heading2 = Font.system(size: 24, weight: .semibold)
        .leading(.init(1.1))

    /// Whimsical Primary font style: Candal, 32pt
    /// Special decorative font
    static let whimsicalPrimary = Font.custom("Candal", size: 32)
        .weight(.regular)
        .leading(.init(1.25))
}

extension Font {
    func leading(_ lineHeight: CGFloat) -> Font {
        // Note: SwiftUI doesn't directly support line height multipliers
        // This is a placeholder for the API. Actual line height would need
        // to be applied using Text view modifiers
        return self
    }
}

// MARK: - Text Modifiers for Line Height
extension View {
    func lineSpacing(for style: TypographyStyle) -> some View {
        switch style {
        case .primary:
            return self.lineSpacing(35.2 - 32)  // lineHeight 1.1 * fontSize
        case .subtitle:
            return self.lineSpacing(20 - 14)
        case .heading1:
            return self.lineSpacing(31.64 - 28)  // lineHeight 1.13 * fontSize
        case .heading2:
            return self.lineSpacing(26.4 - 24)  // lineHeight 1.1 * fontSize
        case .whimsicalPrimary:
            return self.lineSpacing(40 - 32)  // lineHeight 1.25 * fontSize
        }
    }
}

enum TypographyStyle {
    case primary
    case subtitle
    case heading1
    case heading2
    case whimsicalPrimary
}
