import Foundation
import SwiftData

enum SegmentKind: String, Codable, CaseIterable {
    case work
    case rest
    case pause
    case warmup
    case cooldown
    case custom
}

@Model
final class Workout {
    var id: UUID
    var name: String
    var notes: String?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Segment.workout)
    var segments: [Segment]
    var totalRounds: Int

    init(name: String,
         notes: String? = nil,
         segments: [Segment] = [],
         totalRounds: Int = 1,
         now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.notes = notes
        self.createdAt = now
        self.updatedAt = now
        self.segments = segments
        self.totalRounds = max(1, totalRounds)
    }

    var totalDuration: TimeInterval {
        let onePass = segments.reduce(0) { $0 + $1.duration }
        return onePass * TimeInterval(max(1, totalRounds))
    }
}

@Model
final class Segment {
    var id: UUID
    var workout: Workout?
    var order: Int
    var kindRaw: String
    var title: String?
    var duration: TimeInterval

    init(order: Int,
         kind: SegmentKind,
         duration: TimeInterval,
         title: String? = nil) {
        self.id = UUID()
        self.order = order
        self.kindRaw = kind.rawValue
        self.duration = max(0, duration)
        self.title = title
    }

    var kind: SegmentKind {
        get { SegmentKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }
}
