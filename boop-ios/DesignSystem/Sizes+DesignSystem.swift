//
//  Sizes+DesignSystem.swift
//  boop-ios
//
//  Design tokens for component dimensions
//

import Foundation

// MARK: - Component Sizes
enum ComponentSize {
    /// Standard card height: 96pt
    static let cardHeight: CGFloat = 96

    /// Standard button/thumbnail size: 44pt
    static let buttonSize: CGFloat = 44

    /// Page header height: 64pt
    static let pageHeaderHeight: CGFloat = 64
}

// MARK: - Thumbnail Sizes
enum ThumbnailSize {
    /// Single thumbnail size: 44pt
    static let single: CGFloat = 44

    /// Double thumbnail container width: 76pt
    static let doubleWidth: CGFloat = 76

    /// Triple thumbnail container width: 98pt
    static let tripleWidth: CGFloat = 98

    /// Thumbnail border width: 2pt
    static let borderWidth: CGFloat = 2
}

// MARK: - Thumbnail Offsets (for overlapping)
enum ThumbnailOffset {
    /// Offset for second thumbnail in double stack: 32pt
    /// Calculation: 44 (single) * 2 - 76 (doubleWidth) = 12pt overlap
    /// So offset = 44 - 12 = 32pt
    static let double: CGFloat = 32

    /// Offset for middle thumbnail in triple stack: 27pt
    static let middle: CGFloat = 27

    /// Offset for back thumbnail in triple stack: 54pt
    static let back: CGFloat = 54
}

// MARK: - Icon Sizes
enum IconSize {
    /// Small icon (chevron, etc): 8pt width
    static let xsmall: CGFloat = 8

    /// Standard icon size: 17pt
    static let standard: CGFloat = 17

    /// Large icon size: 24pt
    static let large: CGFloat = 24

    /// Page control dot: 8pt
    static let dot: CGFloat = 8
}

// MARK: - Text Sizes (for when using system fonts)
enum TextSize {
    /// Primary/Large title: 32pt
    static let primary: CGFloat = 32

    /// Heading 1: 28pt
    static let heading1: CGFloat = 28

    /// Heading 2: 24pt
    static let heading2: CGFloat = 24

    /// Body: 17pt
    static let body: CGFloat = 17

    /// Subtitle/Caption: 14pt
    static let subtitle: CGFloat = 14
}

// MARK: - Layout Constants
enum LayoutConstant {
    /// Standard gap between thumbnails: 8pt
    static let thumbnailGap: CGFloat = 8

    /// Content spacing within card: 5pt
    static let cardContentGap: CGFloat = 5
}

// MARK: - Map Sizes
enum MapSize {
    /// Height of the map preview shown in interaction cards: 160pt
    static let cardMapHeight: CGFloat = 160
    
    /// Radius of the pins in the map preview show in interaction cards: 10pt
    static let pinRadius: CGFloat = 10
    
    /// Width of the border of pins in the map preview show in interaction cards: 2pt
    static let pinBorderWidth: CGFloat = 2
}

// MARK: - Animation Durations
enum AnimationDuration {
    /// Quick animations (micro-interactions): 0.2s
    static let quick: Double = 0.2

    /// Standard animations (transitions): 0.3s
    static let standard: Double = 0.3

    /// Modal presentations and overlays: 1.0s
    static let modal: Double = 1.0
}
