//
//  ModelContextProvider.swift
//  boop-ios
//
//  Single owner of the shared ModelContext used by all repositories.
//

import Foundation
import SwiftData

@MainActor
final class ModelContextProvider {
    static let shared = ModelContextProvider()
    private(set) var context: ModelContext?

    private init() {}

    func setModelContainer(_ container: ModelContainer) {
        self.context = ModelContext(container)
    }
}
