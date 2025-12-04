//
//  BoopInteraction.swift
//  boop-ios
//
//  Model for Boop interaction data displayed in cards
//

import Foundation
import SwiftUI

struct BoopInteraction: Identifiable {
    let id = UUID()
    let title: String
    let location: String
    let date: String
    let time: String
    let thumbnails: [UIImage]

    var thumbnailCount: Int {
        thumbnails.count
    }

    // Sample data for preview
    static let samples: [BoopInteraction] = [
        BoopInteraction(
            title: "Hang with Aparna",
            location: "Stuytown, NYC",
            date: "Yesterday",
            time: "3pm",
            thumbnails: []
        ),
        BoopInteraction(
            title: "Anish, Sarem...",
            location: "John St, NYC",
            date: "Last Wed",
            time: "6pm",
            thumbnails: []
        ),
        BoopInteraction(
            title: "Anu, Jesse, Sarem",
            location: "Joyface, NYC",
            date: "Last Year",
            time: "11pm",
            thumbnails: []
        )
    ]
}
