//
//  BoopView.swift
//  boop-ios
//
//  Created by Anu Lal on 11/26/25.
//

import SwiftUI
import SwiftData

struct BoopView: View {
    @StateObject private var boopViewModel = BoopViewModel()
    @Environment(\.modelContext) private var modelContext
    @Query private var entries: [Entry]
    
    var showBoop: Bool {
        !boopViewModel.boopAnimationQueue.isEmpty
    }
    
    var body: some View {
        ZStack {
            Text("Timeline").foregroundColor(Color.white).font(.title).fontWeight(.bold).fontDesign(.rounded)
            Spacer()
            List {
                ForEach(entries) { entry in
                    NavigationLink {
                        Text("Boop at \(entry.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard)) from \(entry.user)")
                    } label: {
                        Text(entry.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                    }
                }
                .onDelete(perform: deleteEntry)
            }.background(Color.pink)
            
            if showBoop {
                Color.black.opacity(0.4).ignoresSafeArea() // dim background
                VStack(spacing: 20) {
                    Text("Boop!").font(.title)
                    Text(boopViewModel.getLastBoopUserFromAnimationQueue())
                }.background(Color.pink)
            }
        }
        .animation(.easeInOut(duration: 10), value: showBoop)
        .onDisappear(perform: insertEntry)
    }
        
    private func deleteEntry(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(entries[index])
            }
        }
    }
    
    private func insertEntry() {
        withAnimation {
            let userString = boopViewModel.getBoopUserFromAnimationQueueAndRemove()
            if (userString != "") {
                let user = UUID(uuidString: userString)
                if let nonnulluser = user {
                    modelContext.insert(Entry(user: nonnulluser))
                }
            }
        }
    }
}
#Preview {
    ContentView()
        .modelContainer(for: Entry.self, inMemory: true)
}
