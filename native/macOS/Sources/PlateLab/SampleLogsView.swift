import SwiftUI
import SwiftData

struct SampleLogsView: View {
    @Query private var events: [SampleEvent]
    @Query(sort: \Aliquot.label) private var samples: [Aliquot]
    @AppStorage("proteinConcentrationDisplayUnit") private var concentrationUnit: ProteinConcentrationUnit = .milligramsPerMilliliter
    @State private var search = ""
    @State private var sampleID: UUID?
    @State private var details: Aliquot?

    private var entries: [SampleEvent] {
        SampleLog.entries(events, sampleID: sampleID, search: search, concentrationUnit: concentrationUnit)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Sample logs").font(.title2.bold())
                    Text("All sample activity, newest first").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sample", selection: $sampleID) {
                    Text("All samples").tag(nil as UUID?)
                    ForEach(samples) { sample in
                        Text(sample.label + (sample.archived ? " (archived)" : "")).tag(Optional(sample.id))
                    }
                }.labelsHidden().frame(width: 170).accessibilityLabel("Filter logs by sample")
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search logs", text: $search).textFieldStyle(.plain)
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear log search")
                    }
                }.padding(10).frame(width: 230).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }.padding(22).background(Color(nsColor: .windowBackgroundColor))
            Divider()
            HStack(spacing: 24) {
                Text("Date & time").frame(width: 145, alignment: .leading)
                Text("Sample").frame(width: 150, alignment: .leading)
                Text("Activity & reason").frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            Divider()
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(events.isEmpty ? "No logs yet" : "No matching logs", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text(events.isEmpty ? "Withdrawals, thaws, and sample changes appear here automatically." : "Try another sample or search term.")
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { event in
                            row(event)
                            Divider()
                        }
                    }.padding(.horizontal, 24)
                }
            }
            Divider()
            HStack {
                Text("\(entries.count) \(entries.count == 1 ? "entry" : "entries")")
                Spacer()
                Text("Click a sample name for its full history")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
                .background(Color(nsColor: .windowBackgroundColor))
        }.background(Color(nsColor: .textBackgroundColor))
            .sheet(item: $details) { SampleDetailsView(aliquot: $0) }
    }

    private func row(_ event: SampleEvent) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(event.date?.formatted(date: .abbreviated, time: .omitted) ?? "Undated")
                if let date = event.date, !event.dateOnly {
                    Text(date.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary).monospacedDigit()
                } else if event.dateOnly && event.date != nil {
                    Text("Time not recorded").font(.caption).foregroundStyle(.secondary)
                }
            }.frame(width: 145, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                if let sample = event.aliquot {
                    Button(sample.label) { details = sample }.buttonStyle(.plain).foregroundStyle(.tint).fontWeight(.semibold)
                    if let variant = sample.batch?.variant, !variant.isEmpty { Text(variant).font(.caption).foregroundStyle(.secondary) }
                    if sample.archived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
                } else { Text("Unknown sample").foregroundStyle(.secondary) }
            }.frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                Text(event.activityTitle(concentrationUnit: concentrationUnit)).fontWeight(.medium)
                if !event.notes.isEmpty { Text(event.notes).foregroundStyle(.secondary) }
                if !event.experiment.isEmpty { Label(event.experiment, systemImage: "flask").font(.callout).foregroundStyle(.secondary) }
                if let location = event.newLocation, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").font(.callout).foregroundStyle(.secondary) }
                if !event.wells.isEmpty { Text("Wells: \(event.wells)").font(.callout).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
        }.padding(.vertical, 18)
    }
}
