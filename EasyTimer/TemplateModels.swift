import Foundation
import SwiftData

@Model
final class TemplateFolder {
    @Attribute(.unique) var id: UUID
    var name: String
    @Relationship(deleteRule: .cascade) var templates: [TemplateItem]

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.templates = []
    }
}

@Model
final class TemplateItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var totalRounds: Int
    // Persist segments as value types for simplicity
    var segments: [SegmentData]

    init(name: String, totalRounds: Int, segments: [SegmentData]) {
        self.id = UUID()
        self.name = name
        self.totalRounds = totalRounds
        self.segments = segments
    }
}

// Lightweight representation of a segment for persistence inside a template
struct SegmentData: Codable, Hashable {
    var order: Int
    var kind: SegmentKindData
    var duration: TimeInterval
    var title: String?
}

enum SegmentKindData: String, Codable, Hashable {
    case work
    case rest
}

// MARK: - Conversions to/from runtime models
extension Workout {
    static func fromTemplate(_ t: TemplateItem) -> Workout {
        let w = Workout(name: t.name, totalRounds: t.totalRounds)
        w.segments = t.segments.map { sd in
            Segment(order: sd.order,
                    kind: sd.kind == .work ? .work : .rest,
                    duration: sd.duration,
                    title: sd.title)
        }
        return w
    }
}

extension TemplateItem {
    static func fromWorkout(_ w: Workout) -> TemplateItem {
        let segs = w.segments.sorted { $0.order < $1.order }.map { s in
            SegmentData(order: s.order,
                        kind: s.kind == .work ? .work : .rest,
                        duration: s.duration,
                        title: s.title)
        }
        return TemplateItem(name: w.name, totalRounds: w.totalRounds, segments: segs)
    }
}
