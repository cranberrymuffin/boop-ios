//
//  LiveActivityManager.swift
//  boop-ios
//
//  Created by Aparna Natarajan on 02/09/26.
//

import Foundation
import ActivityKit
import UserNotifications

@MainActor
class LiveActivityManager {
    static let shared = LiveActivityManager()
    private var currentActivity: Activity<BoopLiveActivityAttributes>?

    func startBoopLiveActivity(
        contactName: String,
        contactID: UUID,
        interactionID: UUID? = nil
    ) {
        if #available(iOS 16.1, *) {
            let authInfo = ActivityAuthorizationInfo()
            print("📊 Activity Authorization - Enabled: \(authInfo.areActivitiesEnabled)")
            print("📊 Frequent pushes enabled: \(authInfo.frequentPushesEnabled)")
            logNotificationSettings()

            guard authInfo.areActivitiesEnabled else {
                print("⚠️ Live Activities are not enabled on this device")
                return
            }

            // End existing activity if any before starting new one
            if let existing = currentActivity {
                Task {
                    await existing.end(nil, dismissalPolicy: .immediate)
                }
                currentActivity = nil
            }

            let attributes = BoopLiveActivityAttributes()
            let contentState = BoopLiveActivityAttributes.ContentState(
                contactName: contactName,
                contactID: contactID,
                interactionID: interactionID,
                boopTime: Date()
            )

            do {
                let staleDate = Date().addingTimeInterval(300) // 5 minutes
                let content = ActivityContent(state: contentState, staleDate: staleDate)
                let activity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
                currentActivity = activity
                print("✅ Live Activity started! id=\(activity.id) contact=\(contactName)")
            } catch {
                print("❌ Failed to start Live Activity: \(error.localizedDescription)")
                if let error = error as NSError? {
                    print("Error code: \(error.code), domain: \(error.domain)")
                    print("Error userInfo: \(error.userInfo)")
                }
            }
        }
    }
    
    func updateBoopLiveActivity(
        contactName: String,
        contactID: UUID,
        interactionID: UUID?
    ) async {
        if #available(iOS 16.1, *) {
            guard let activity = currentActivity else {
                print("⚠️ No active Live Activity to update")
                return
            }
            
            let updatedState = BoopLiveActivityAttributes.ContentState(
                contactName: contactName,
                contactID: contactID,
                interactionID: interactionID,
                boopTime: Date()
            )
            
            let content = ActivityContent(state: updatedState, staleDate: Date().addingTimeInterval(300))
            await activity.update(content)
            print("✅ Live Activity updated! contact=\(contactName)")
        }
    }
    
    func endBoopLiveActivity() async {
        if #available(iOS 16.1, *) {
            guard let activity = currentActivity else {
                print("⚠️ No active Live Activity to end")
                return
            }
            
            await activity.end(nil, dismissalPolicy: .default)
            currentActivity = nil
            print("✅ Live Activity ended")
        }
    }

    private func logNotificationSettings() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            print("📊 Notification settings: status=\(settings.authorizationStatus.rawValue) alerts=\(settings.alertSetting.rawValue)")
        }
    }
}
