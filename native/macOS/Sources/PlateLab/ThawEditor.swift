import SwiftUI
import SwiftData

// Shared by the main window and the sample details sheet, so the dialog is
// centered in whichever surface the user is currently editing.
struct SampleEditorOverlay: ViewModifier {
    @EnvironmentObject var app: AppState
    var inSheet = false
    private var edit: SampleValueEdit? { app.valueEdit.flatMap { $0.inSheet == inSheet ? $0 : nil } }

    func body(content: Content) -> some View {
        content.disabled(edit != nil).accessibilityHidden(edit != nil)
            .overlay {
                if let edit {
                    ZStack {
                        Color.black.opacity(0.12).ignoresSafeArea()
                            .contentShape(Rectangle()).onTapGesture { }.accessibilityHidden(true)
                        Group {
                            if edit.action == .thaw {
                                ThawEditor(sample: edit.sample) { app.valueEdit = nil }
                            } else {
                                SampleValueEditor(sample: edit.sample, action: edit.action) { app.valueEdit = nil }
                            }
                        }
                        .id(edit.id)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.7)))
                        .shadow(color: .black.opacity(0.16), radius: 24, y: 8)
                        .accessibilityAddTraits(.isModal)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
    }
}

struct ThawEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sample: Aliquot
    let close: () -> Void
    @State private var expectedVolume: Double?
    @State private var expectedSequence: Int
    @State private var volumeChanged: Bool?
    @State private var measured: Bool?
    @State private var volume = ""
    @State private var error: String?
    @FocusState private var focusVolume: Bool

    init(sample: Aliquot, close: @escaping () -> Void) {
        self.sample = sample; self.close = close
        _expectedVolume = State(initialValue: sample.remainingUL)
        _expectedSequence = State(initialValue: sample.events.map(\.sequence).max() ?? 0)
    }

    private var ready: Bool {
        volumeChanged != nil && measured != nil && (volumeChanged == false || !clean(volume).isEmpty)
    }

    private var resultingVolume: Double? {
        if volumeChanged == true { return Double(clean(volume)).flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
        return expectedVolume.map { $0 - (measured == true ? concentrationMeasurementVolumeUL : 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(sample.label).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text("Record thaw").font(.title3.weight(.semibold))
                Text("Currently recorded: \(volumeLabel(expectedVolume))")
                    .font(.callout).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Has the volume changed?").font(.headline)
                Text("After centrifuging and transferring to a new tube.")
                    .font(.callout).foregroundStyle(.secondary)
                choice("Volume changed", selection: $volumeChanged)
                if volumeChanged == true {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            TextField("Volume now", text: $volume).textFieldStyle(.plain)
                                .font(.title3.weight(.medium)).monospacedDigit().focused($focusVolume)
                                .accessibilityLabel("Current remaining volume, µL").onSubmit(save)
                            Text("µL").foregroundStyle(.secondary)
                        }
                        .padding(11).background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.teal.opacity(0.3)))
                        Text("Enter what is left now, after any 1.5 µL measurement. This will be the final volume.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Text("Used 1.5 µL to measure concentration?").font(.headline)
                choice("Concentration measurement", selection: $measured)
            }
            if ready, let remaining = resultingVolume, remaining >= 0 {
                Text("Thaws +1  ·  \(volumeLabel(remaining)) remaining")
                    .font(.callout.weight(.medium)).monospacedDigit()
            }
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save thaw", action: save).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction).disabled(!ready)
            }
        }.padding(22).frame(width: 390)
            .onChange(of: volumeChanged) { _, changed in focusVolume = changed == true }
    }

    private func choice(_ label: String, selection: Binding<Bool?>) -> some View {
        HStack(spacing: 10) {
            ForEach([false, true], id: \.self) { value in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                        selection.wrappedValue = value
                        error = nil
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selection.wrappedValue == value ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.wrappedValue == value ? Color.teal : Color.secondary)
                        Text(value ? "Yes" : "No")
                    }.frame(minWidth: 55)
                }.buttonStyle(.bordered)
                    .accessibilityLabel("\(label): \(value ? "Yes" : "No")")
                    .accessibilityValue(selection.wrappedValue == value ? "Selected" : "Not selected")
            }
        }
    }

    private func save() {
        guard ready, let measured else { return }
        do {
            let remaining = volumeChanged == true ? try quantity(volume, name: "remaining volume") : nil
            try Inventory.recordThaw(for: sample, measured: measured, remainingVolume: remaining,
                                     expectedVolume: expectedVolume, expectedSequence: expectedSequence, in: context)
            close()
        } catch { self.error = error.localizedDescription }
    }
}
