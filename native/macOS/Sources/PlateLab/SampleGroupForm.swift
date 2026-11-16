import SwiftUI
import SwiftData

struct SampleGroupForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Aliquot.label) private var samples: [Aliquot]
    let originalName: String?
    let onSave: (String) -> Void
    @State private var name: String
    @State private var members: Set<UUID>
    @State private var error: String?
    @FocusState private var focusName: Bool

    init(name: String? = nil, members: Set<UUID>, onSave: @escaping (String) -> Void) {
        originalName = name
        self.onSave = onSave
        _name = State(initialValue: name ?? "")
        _members = State(initialValue: members)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(originalName == nil ? "New sample group" : "Edit sample group").font(.title2.bold())
            SampleInput(title: "Group name", text: $name, placeholder: "e.g. CSE — Cystathionine gamma-lyase")
                .focused($focusName)
            HStack {
                Text("Samples in this group").fontWeight(.medium)
                Spacer()
                Button("Select all") { members = Set(samples.map(\.id)) }
                Button("Clear") { members = [] }
            }.font(.callout)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(samples) { sample in
                        Toggle(isOn: Binding(get: { members.contains(sample.id) }, set: { included in
                            if included { members.insert(sample.id) } else { members.remove(sample.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(sample.label).fontWeight(.medium)
                                if let variant = sample.batch?.variant, !variant.isEmpty { Text(variant).font(.caption).foregroundStyle(.secondary) }
                                if let group = sample.groupName, group != originalName {
                                    Text("Currently in \(group)").font(.caption).foregroundStyle(.secondary)
                                }
                                if sample.archived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.toggleStyle(.checkbox).padding(.vertical, 10)
                        Divider()
                    }
                }.padding(.horizontal, 12)
            }.frame(height: min(300, CGFloat(samples.count) * 80 + 8))
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            Text("\(members.count) selected · Each tube keeps its own measurements and history.")
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(originalName == nil ? "Create group" : "Save group") { save() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(clean(name).isEmpty || members.isEmpty)
            }
        }.padding(24).frame(width: 560).onAppear { focusName = true }
    }

    private func save() {
        do {
            let saved = try SampleGroups.save(name: name, replacing: originalName, members: members, in: context)
            onSave(saved)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
