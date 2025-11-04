import SwiftUI
import SwiftData

struct TemplateFoldersView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TemplateFolder.name) private var folders: [TemplateFolder]

    @State private var newFolderName: String = ""
    @State private var isCreatingFolder: Bool = false

    var body: some View {
        List {
            Section("Folders") {
                ForEach(folders) { folder in
                    NavigationLink(folder.name) {
                        TemplateFolderView(folder: folder)
                    }
                }
                .onDelete { indexSet in
                    indexSet.map { folders[$0] }.forEach(context.delete)
                    try? context.save()
                }
            }

            Section {
                HStack {
                    TextField("New Folder", text: $newFolderName)
                    Button("Add") {
                        addFolder()
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle("Templates")
    }

    private func addFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let f = TemplateFolder(name: name)
        context.insert(f)
        try? context.save()
        newFolderName = ""
    }
}

struct TemplateFolderView: View {
    @Environment(\.modelContext) private var context
    @State var folder: TemplateFolder

    @State private var newTemplateName: String = ""
    @State private var newTemplateRounds: Int = 1
    @State private var createdTemplate: TemplateItem?

    var body: some View {
        List {
            Section("Templates") {
                ForEach(folder.templates) { t in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(t.name).font(.headline)
                            Text("\(t.totalRounds) rounds • \(t.segments.count) segments")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        NavigationLink("Use") {
                            RunnerView(workout: Workout.fromTemplate(t))
                        }
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { folder.templates[$0] }
                    toDelete.forEach(context.delete)
                    try? context.save()
                }
            }

            Section("Add Template") {
                TextField("Name", text: $newTemplateName)
                HStack {
                    Text("Rounds")
                    Spacer()
                    Text("\(newTemplateRounds)")
                        .foregroundStyle(.secondary)
                    Stepper("", value: $newTemplateRounds, in: 1...100)
                        .labelsHidden()
                }
                Button("Create") {
                    let template = TemplateItem(
                        name: newTemplateName.isEmpty ? "New Template" : newTemplateName,
                        totalRounds: newTemplateRounds,
                        segments: []
                    )
                    folder.templates.append(template)
                    try? context.save()
                    createdTemplate = template
                }
                .disabled(newTemplateRounds < 1)
            }
        }
        .navigationTitle(folder.name)
        .navigationDestination(item: $createdTemplate) { t in
            LegacyTemplateEditorView(template: t)
        }
    }
}

struct LegacyTemplateEditorView: View {
    @Environment(\.modelContext) private var context
    @State var template: TemplateItem

    @State private var isAddingSegment = false
    @State private var segTitle: String = ""
    @State private var segKind: SegmentKindData = .work
    @State private var segDuration: Int = 10

    var body: some View {
        List {
            Section("Segments") {
                ForEach(Array(template.segments.enumerated()), id: \.offset) { idx, seg in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(seg.title ?? (seg.kind == .work ? "Work" : "Rest"))
                            .font(.headline)
                        Text("\(seg.kind == .work ? "Work" : "Rest") • \(Int(seg.duration))s")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Add Segment") { isAddingSegment = true }
            }
        }
        .navigationTitle("Edit \(template.name)")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { try? context.save() }
            }
        }
        .sheet(isPresented: $isAddingSegment) {
            NavigationStack {
                Form {
                    TextField("Title (optional)", text: $segTitle)
                    Picker("Kind", selection: $segKind) {
                        Text("Work").tag(SegmentKindData.work)
                        Text("Rest").tag(SegmentKindData.rest)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text("\(segDuration)s")
                            .foregroundStyle(.secondary)
                        Stepper("", value: $segDuration, in: 1...600)
                            .labelsHidden()
                    }
                }
                .navigationTitle("New Segment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { isAddingSegment = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            let nextOrder = (template.segments.map { $0.order }.max() ?? -1) + 1
                            let newSeg = SegmentData(order: nextOrder,
                                                     kind: segKind,
                                                     duration: TimeInterval(segDuration),
                                                     title: segTitle.isEmpty ? nil : segTitle)
                            template.segments.append(newSeg)
                            try? context.save()
                            // reset
                            segTitle = ""
                            segKind = .work
                            segDuration = 10
                            isAddingSegment = false
                        }
                    }
                }
            }
        }
    }
}

