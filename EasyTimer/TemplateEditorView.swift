import SwiftUI
import SwiftData

struct TemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var template: WorkoutTemplate

    @State private var isAddingBlock = false

    var body: some View {
        Form {
            Section("Template") {
                TextField("Name", text: $template.name)
                TextField("Notes", text: Binding(get: { template.notes ?? "" }, set: { template.notes = $0.isEmpty ? nil : $0 }))
            }

            Section("Blocks") {
                if template.blocks.isEmpty {
                    ContentUnavailableView("No Blocks", systemImage: "square.stack.3d.up.slash", description: Text("Add a block to define sets, reps, and rest."))
                } else {
                    List {
                        ForEach(template.blocks.sorted(by: { $0.order < $1.order })) { block in
                            BlockRow(block: block)
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
        }
        .onChange(of: template.blocks) { _, _ in
            normalizeOrders()
        }
        .onDisappear { try? context.save() }
    }

    private func addBlock() {
        let order = (template.blocks.map { $0.order }.max() ?? -1) + 1
        let block = TemplateBlock(order: order, title: "Block \(order + 1)", sets: 3, reps: 5, workDuration: 7, restBetweenReps: 3, restBetweenSets: 30)
        block.template = template
        template.blocks.append(block)
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
    }

    private func moveBlocks(from source: IndexSet, to destination: Int) {
        var sorted = template.blocks.sorted { $0.order < $1.order }
        sorted.move(fromOffsets: source, toOffset: destination)
        for (i, b) in sorted.enumerated() { b.order = i }
        template.blocks = sorted
    }

    private func normalizeOrders() {
        let sorted = template.blocks.sorted { $0.order < $1.order }
        for (i, b) in sorted.enumerated() { b.order = i }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%dm %02ds", m, s)
    }
}

private struct BlockRow: View {
    @Bindable var block: TemplateBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: Binding(get: { block.title ?? "" }, set: { block.title = $0.isEmpty ? nil : $0 }))
                .font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                // Sets row: label | value | stepper
                GridRow {
                    Text("Sets")
                        .foregroundStyle(.secondary)
                    Text("\(block.sets)")
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    Stepper("", value: $block.sets, in: 1...100)
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
                    Stepper("", value: $block.reps, in: 1...100)
                        .labelsHidden()
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                DurationField(title: "Work", seconds: $block.workDuration)
                DurationField(title: "Rep Rest", seconds: $block.restBetweenReps)
                DurationField(title: "Set Rest", seconds: $block.restBetweenSets)
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
        TemplateBlock(order: 0, title: "Hang", sets: 2, reps: 3, workDuration: 7, restBetweenReps: 3, restBetweenSets: 30)
    ]
    return NavigationStack { TemplateEditorView(template: t) }
        .modelContainer(for: [WorkoutTemplate.self, TemplateBlock.self], inMemory: true)
}
