//
//  ContentView.swift
//  EasyTimer
//
//  Created by James Huang on 11/4/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Workout.createdAt, order: .reverse) private var workouts: [Workout]
    @State private var isPresentingAdd = false

    var body: some View {
        NavigationSplitView {
            Group {
                if workouts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 44))
                            .padding(.bottom, 4)
                        Text("No workouts yet")
                            .font(.headline)
                        Text("Tap the + to create your first interval set.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(workouts) { workout in
                            NavigationLink {
                                RunnerView(workout: workout)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(workout.name).font(.headline)
                                    Text(durationString(workout.totalDuration))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: deleteWorkouts)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: { isPresentingAdd = true }) {
                        Label("Add Workout", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        TemplateListView()
                    } label: {
                        Label("Templates", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .sheet(isPresented: $isPresentingAdd) {
                AddWorkoutSheet { newWorkout in
                    modelContext.insert(newWorkout)
                }
            }
        } detail: {
            Text("Select a workout")
        }
    }

    private func addWorkout() {
        withAnimation {
            let w = Workout(name: "7/3 x 6", totalRounds: 6)
            w.segments = [
                Segment(order: 0, kind: .work, duration: 7, title: "Hang"),
                Segment(order: 1, kind: .rest, duration: 3, title: "Rest")
            ]
            modelContext.insert(w)
        }
    }

    private func deleteWorkouts(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(workouts[index])
            }
        }
    }
}

func durationString(_ t: TimeInterval) -> String {
    let total = Int(t.rounded())
    let m = total / 60
    let s = total % 60
    return String(format: "%dm %02ds", m, s)
}

#Preview {
    ContentView()
        .modelContainer(for: [Workout.self, Segment.self], inMemory: true)
}

import SwiftUI

struct AddWorkoutSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "7/3 x 6"
    @State private var rounds: Int = 6
    @State private var workSec: Int = 7
    @State private var restSec: Int = 3

    let onSave: (Workout) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    Stepper("Rounds: \(rounds)", value: $rounds, in: 1...50)
                }
                Section("Intervals") {
                    Stepper("Work: \(workSec)s", value: $workSec, in: 1...600)
                    Stepper("Rest: \(restSec)s", value: $restSec, in: 0...600)
                }
                Section("Preview") {
                    Text("\(name) • Total ~ \(durationString(totalDuration))")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let w = Workout(name: name, totalRounds: rounds)
                        w.segments = [
                            Segment(order: 0, kind: .work, duration: TimeInterval(workSec), title: "Hang"),
                            Segment(order: 1, kind: .rest, duration: TimeInterval(restSec), title: "Rest")
                        ]
                        onSave(w)
                        dismiss()
                    }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var totalDuration: TimeInterval {
        let perRound = TimeInterval(workSec + restSec)
        return perRound * TimeInterval(rounds)
    }
}
