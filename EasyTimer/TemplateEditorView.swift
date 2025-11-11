import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var template: WorkoutTemplate

    @State private var isAddingBlock = false
    @State private var isDirty = false

    var body: some View {
        Form {
            Section("Template") {
                TextField("Name", text: Binding(
                    get: { template.name },
                    set: { template.name = $0; markDirty() }
                ))
                TextField(
                    "Notes",
                    text: Binding(
                        get: { template.notes ?? "" },
                        set: { let v = $0.isEmpty ? nil : $0; template.notes = v; markDirty() }
                    )
                )
            }

            Section("Blocks") {
                if template.blocks.isEmpty {
                    ContentUnavailableView("No Blocks", systemImage: "square.stack.3d.up.slash", description: Text("Add a block to define sets, reps, and rest."))
                } else {
                    List {
                        ForEach(template.blocks.sorted(by: { $0.order < $1.order })) { block in
                            BlockRow(block: block, onChange: markDirty)
                        }
                        .onDelete(perform: deleteBlocks)
                        .onMove(perform: moveBlocks)
                    }
                    .frame(minHeight: 200)
                }

                Button {
                    addBlock()
                } label: {
                    Label("Add Block", systemImage: "plus")
                }
            }

            Section("Preview") {
                let workout = template.instantiate(toRounds: 1)
                Text("Segments: \(workout.segments.count)")
                Text("Training Time: \(formatDuration(workout.totalDuration))")
            }
        }
        .navigationTitle("Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { EditButton() }
#if canImport(UIKit) && (os(iOS) || os(tvOS))
            ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { hideKeyboard() } }
#endif
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    normalizeOrders()
                    try? context.save()
                    isDirty = false
                    // Do NOT dismiss here; stay on the editor. Back button will pop.
                }
                .disabled(!isDirty)
            }
        }
        // Mark dirty when blocks array changes (add/remove/reorder)
        .onChange(of: template.blocks) { _, _ in
            normalizeOrders()
            markDirty()
        }
        // Mark dirty when any block’s content changes by observing a snapshot of relevant fields
        .onChange(of: blocksSnapshot(template.blocks)) { _, _ in
            markDirty()
        }
        .onDisappear { try? context.save() }
    }

    private func addBlock() {
        let order = (template.blocks.map { $0.order }.max() ?? -1) + 1
        let block = TemplateBlock(order: order, title: "Block \(order + 1)", sets: 3, reps: 5, workDuration: 7, restBetweenReps: 3, restBetweenSets: 30)
        block.template = template
        template.blocks.append(block)
        markDirty()
    }

    private func deleteBlocks(offsets: IndexSet) {
        let sorted = template.blocks.sorted { $0.order < $1.order }
        for index in offsets {
            let block = sorted[index]
            if let idx = template.blocks.firstIndex(where: { $0.id == block.id }) {
                template.blocks.remove(at: idx)
                context.delete(block)
            }
        }
        normalizeOrders()
        markDirty()
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var sorted = template.blocks.sorted { $0.order < $1.order }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (i, b) in sorted.enumerated() { b.order = i }
        template.blocks = sorted
        markDirty()
    }

    private func normalizeOrders() {
        let sorted = template.blocks.sorted { $0.order < $1.order }
        for (i, b) in sorted.enumerated() { b.order = i }
    }

    private func blocksSnapshot(_ blocks: [TemplateBlock]) -> [BlockSnapshot] {
        // Create a lightweight, comparable snapshot of each block to detect edits
        blocks.sorted { $0.order < $1.order }.map {
            BlockSnapshot(id: $0.id,
                          title: $0.title ?? "",
                          sets: $0.sets,
                          reps: $0.reps,
                          work: $0.workDuration,
                          repRest: $0.restBetweenReps,
                          setRest: $0.restBetweenSets,
                          order: $0.order)
        }
    }

    private func markDirty() {
        if !isDirty { isDirty = true }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%dm %02ds", m, s)
    }
}

private struct BlockSnapshot: Equatable, Hashable {
    let id: UUID
    let title: String
    let sets: Int
    let reps: Int
    let work: TimeInterval
    let repRest: TimeInterval
    let setRest: TimeInterval
    let order: Int
}

private struct BlockRow: View {
    @Bindable var block: TemplateBlock
    var onChange: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: Binding(
                get: { block.title ?? "" },
                set: { block.title = $0.isEmpty ? nil : $0; onChange() }
            ))
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                // Sets row: label | value | stepper
                GridRow {
                    Text("Sets")
                        .foregroundStyle(.secondary)
                    Text("\(block.sets)")
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    Stepper("", value: Binding(
                        get: { block.sets },
                        set: { block.sets = $0; onChange() }
                    ), in: 1...100)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
                // Reps row: label | value | stepper
                GridRow {
                    Text("Reps")
                        .foregroundStyle(.secondary)
                    Text("\(block.reps)")
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    Stepper("", value: Binding(
                        get: { block.reps },
                        set: { block.reps = $0; onChange() }
                    ), in: 1...100)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                DurationField(title: "Work", seconds: Binding(
                    get: { block.workDuration },
                    set: { block.workDuration = $0; onChange() }
                ))
                DurationField(title: "Rep Rest", seconds: Binding(
                    get: { block.restBetweenReps },
                    set: { block.restBetweenReps = $0; onChange() }
                ))
                DurationField(title: "Set Rest", seconds: Binding(
                    get: { block.restBetweenSets },
                    set: { block.restBetweenSets = $0; onChange() }
                ))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DurationField: View {
    let title: String
    @Binding var seconds: TimeInterval

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField("sec", value: $seconds, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("s").foregroundStyle(.secondary)
            }
        }
    }
}

#if canImport(UIKit) && (os(iOS) || os(tvOS))
import UIKit
private extension View {
    func hideKeyboard() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
#endif

#Preview {
    let t = WorkoutTemplate(name: "Sample")
    t.blocks = [
        TemplateBlock(order: 0, title: "Name Your Workout", sets: 2, reps: 3, workDuration: 7, restBetweenReps: 3, restBetweenSets: 30)
    ]
    return NavigationStack { TemplateEditorView(template: t) }
        .modelContainer(for: [WorkoutTemplate.self, TemplateBlock.self], inMemory: true)
}
