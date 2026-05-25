//
//  boop_iosApp.swift
//  boop-ios
//
//  Created by Aparna Natarajan on 10/30/25.
//

import SwiftUI
import SwiftData

@main
struct boop_iosApp: App {
    private var schema: Schema
    private var modelConfiguration: ModelConfiguration
    @State var sharedModelContainer: ModelContainer?
    @StateObject private var boopManager = BoopManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var supabaseManager = SupabaseManager.shared
    init() {
        self.schema = Schema([
                Contact.self,
                BoopInteraction.self,
                NotificationIntent.self,
            ])
        self.modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let configurationUrl = self.modelConfiguration.url
        Task {
            await StorageCoordinator.shared.initialize(with: configurationUrl)
        }
    }
    
    @MainActor
    private func setModelContainer() async {
        do {
            try await StorageCoordinator.shared.waitForInitialization()
            sharedModelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Unable to create model container \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if let container = sharedModelContainer {
                    RootView()
                        .modelContainer(container)
                        .environmentObject(boopManager)
                        .environmentObject(locationManager)
                        .environmentObject(supabaseManager)
                } else {
                    VStack
                    {
                        Spacer()
                        ProgressView("Getting Boop Ready for you...")
                        Spacer()
                    }
                }
            }
            .task {
                await setModelContainer()
                locationManager.requestPermissionIfNeeded()
                if let container = sharedModelContainer {
                    ModelContextProvider.shared.setModelContainer(container)
                }
                boopManager.setLocationManager(locationManager)
                await supabaseManager.restoreSession()

                // One-time data migration: merge duplicate interactions per session
                if !UserDefaults.standard.bool(forKey: "hasRunSessionMergeV2") {
                    BoopInteractionRepository.shared.mergeSessionDuplicates()
                    UserDefaults.standard.set(true, forKey: "hasRunSessionMergeV2")
                }

                let granted = await NotificationManager.shared.requestAuthorization()
                if let container = sharedModelContainer {
                    let scheduler = NotificationScheduler(modelContainer: container)
                    await scheduler.syncAllSchedules()

                    if granted {
                        await scheduler.setSchedule(
                            type: .weeklyPlanning,
                            trigger: .cadence(
                                on: DateComponents(hour: 17, minute: 0, weekday: 1),
                                every: .weekly
                            )
                        )
                    }
                }
            }
        }
    }
}
