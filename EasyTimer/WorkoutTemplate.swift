import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var id: UUID
    var name: String
    var notes: String?
    @Relationship(deleteRule: .cascade, inverse: \TemplateBlock.template)
    var blocks: [TemplateBlock]

    init(name: String, notes: String? = nil, blocks: [TemplateBlock] = []) {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.blocks = blocks
    }

    // Generate a concrete Workout and Segments from this template
    func instantiate(toRounds: Int = 1) -> Workout {
        let workout = Workout(name: name, notes: notes, segments: [], totalRounds: toRounds)
        var order = 0
        for block in blocks.sorted(by: { $0.order < $1.order }) {
            // Each set consists of `reps` of work + restBetweenReps, and a restBetweenSets between sets
            for setIndex in 0..<block.sets {
                for repIndex in 0..<block.reps {
                    // Work segment
                    let workTitle = block.title?.isEmpty == false ? block.title : "Work"
                    workout.segments.append(Segment(order: order, kind: .work, duration: block.workDuration, title: workTitle))
                    order += 1
                    // Rest between reps (skip after last rep)
                    if repIndex < block.reps - 1, block.restBetweenReps > 0 {
                        workout.segments.append(Segment(order: order, kind: .rest, duration: block.restBetweenReps, title: "Rest"))
                        order += 1
                    }
                }
                // Rest between sets (skip after last set)
                if setIndex < block.sets - 1, block.restBetweenSets > 0 {
                    workout.segments.append(Segment(order: order, kind: .rest, duration: block.restBetweenSets, title: "Set Rest"))
                    order += 1
                }
            }
        }
        return workout
    }
}

@Model
final class TemplateBlock {
    var id: UUID
    var template: WorkoutTemplate?
    var order: Int
    var title: String?
    var sets: Int
    var reps: Int
    var workDuration: TimeInterval
    var restBetweenReps: TimeInterval
    var restBetweenSets: TimeInterval

    init(order: Int,
         title: String? = nil,
         sets: Int,
         reps: Int,
         workDuration: TimeInterval,
         restBetweenReps: TimeInterval,
         restBetweenSets: TimeInterval) {
        self.id = UUID()
        self.order = order
        self.title = title
        self.sets = max(1, sets)
        self.reps = max(1, reps)
        self.workDuration = max(0, workDuration)
        self.restBetweenReps = max(0, restBetweenReps)
        self.restBetweenSets = max(0, restBetweenSets)
    }
}
