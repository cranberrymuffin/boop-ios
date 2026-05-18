//
//  BoopLiveActivityLiveActivity.swift
//  BoopLiveActivity
//
//  Created by Aparna Natarajan on 2/9/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BoopLiveActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BoopLiveActivityAttributes.self) { context in
            // Lock screen/banner UI
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Booped with")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(context.state.contactName)
                        .font(.headline)
                        .fontWeight(.semibold)
                }

                Spacer()

                Link(destination: cameraLink(for: context.state)) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .activityBackgroundTint(Color(UIColor.systemBackground))
            .activitySystemActionForegroundColor(Color("accentPrimary"))
            .widgetURL(deepLink(for: context.state))

        } dynamicIsland: { context in
            DynamicIsland {
                
                DynamicIslandExpandedRegion(.trailing) {
                    Link(destination: cameraLink(for: context.state)) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundColor(Color("accentPrimary"))
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 4) {
                        Text("Booped with")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(context.state.contactName)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    .padding(.vertical, 4)
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                Text(context.state.contactName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            } minimal: {
                EmptyView()
            }
            .widgetURL(deepLink(for: context.state))
        }
    }
    
    private func deepLink(for state: BoopLiveActivityAttributes.ContentState) -> URL {
        if let interactionID = state.interactionID {
            return URL(string: "boop://timeline/\(interactionID.uuidString)")!
        } else {
            return URL(string: "boop://timeline")!
        }
    }

    private func cameraLink(for state: BoopLiveActivityAttributes.ContentState) -> URL {
        if let interactionID = state.interactionID {
            return URL(string: "boop://timeline/\(interactionID.uuidString)/camera")!
        } else {
            return URL(string: "boop://timeline")!
        }
    }
}

#if DEBUG
extension BoopLiveActivityAttributes {
    fileprivate static var preview: BoopLiveActivityAttributes {
        BoopLiveActivityAttributes()
    }
}

extension BoopLiveActivityAttributes.ContentState {
    fileprivate static var preview: BoopLiveActivityAttributes.ContentState {
        BoopLiveActivityAttributes.ContentState(
            contactName: "Sarah Chen",
            contactID: UUID(),
            interactionID: UUID(),
            boopTime: Date().addingTimeInterval(-300) // 5 minutes ago
        )
    }
}

#Preview("Lock Screen", as: .content, using: BoopLiveActivityAttributes.preview) {
    BoopLiveActivityLiveActivity()
} contentStates: {
    BoopLiveActivityAttributes.ContentState.preview
}
#endif
