//
//  EasyTimerApp.swift
//  EasyTimer
//
//  Created by James Huang on 11/4/25.
//

import SwiftUI
import SwiftData

@main
struct EasyTimerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            WorkoutTemplate.self,
            TemplateBlock.self,
            Workout.self,
            Segment.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
