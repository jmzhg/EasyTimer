import SwiftUI
import SwiftData

struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.name) private var templates: [WorkoutTemplate]

    // Track which templates have been added to a workout in this session
    @State private var addedTemplateIDs: Set<UUID> = []

    var body: some View {
        List {
            ForEach(templates) { template in
                HStack {
                    NavigationLink {
                        TemplateEditorView(template: template)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(template.name).font(.headline)
                            Text("\(template.blocks.count) block(s)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    let isAdded = addedTemplateIDs.contains(template.id)
                    Button(isAdded ? "Added to workout" : "Add to workout") {
                        let w = template.instantiate(toRounds: 1)
                        context.insert(w)
                        addedTemplateIDs.insert(template.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAdded)
                }
            }
            .onDelete(perform: deleteTemplates)
        }
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
            ToolbarItem {
                Button(action: addSampleTemplate) {
                    Label("Add Template", systemImage: "plus")
                }
            }
        }
    }

    private func addSampleTemplate() {
        let t = WorkoutTemplate(name: "Hangboard: 7/3 x 6")
        t.blocks = [
            TemplateBlock(order: 0, title: "Hang", sets: 6, reps: 1, workDuration: 7, restBetweenReps: 0, restBetweenSets: 3)
        ]
        context.insert(t)
    }

    private func deleteTemplates(offsets: IndexSet) {
        for i in offsets { context.delete(templates[i]) }
    }
}

#Preview {
    NavigationStack {
        TemplateListView()
    }
    .modelContainer(for: [WorkoutTemplate.self, TemplateBlock.self, Workout.self, Segment.self], inMemory: true)
}
