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
        GeometryReader { size in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    if size.size.width < 780 {
                        heading
                        HStack(spacing: 12) { sampleFilter; searchField }
                    } else {
                        HStack(spacing: 20) { heading; Spacer(); sampleFilter; searchField.frame(width: 230) }
                    }
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Color(nsColor: .windowBackgroundColor))
                Divider()
                if size.size.width >= 780 {
                    HStack(spacing: 24) {
                        Text("Date & time").frame(width: 145, alignment: .leading)
                        Text("Sample").frame(width: 150, alignment: .leading)
                        Text("Activity & reason").frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
                    Divider()
                }
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
                                row(event, compact: size.size.width < 780)
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
        }
        .sheet(item: $details) { SampleDetailsView(aliquot: $0) }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Sample logs").font(.title2.bold())
            Text("All sample activity, newest first").font(.callout).foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var sampleFilter: some View {
        Picker("Sample", selection: $sampleID) {
            Text("All samples").tag(nil as UUID?)
            ForEach(samples) { sample in
                Text(sample.label + (sample.archived ? " (archived)" : "")).tag(Optional(sample.id))
            }
        }.labelsHidden().frame(width: 170).accessibilityLabel("Filter logs by sample")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search logs", text: $search).textFieldStyle(.plain)
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear log search")
            }
        }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ event: SampleEvent, compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        sampleLabel(event)
                        Spacer(minLength: 16)
                        timestamp(event).font(.caption)
                    }
                    activity(event)
                }
            } else {
                HStack(alignment: .top, spacing: 24) {
                    timestamp(event).frame(width: 145, alignment: .leading)
                    sampleLabel(event).frame(width: 150, alignment: .leading)
                    activity(event)
                }
            }
        }.padding(.vertical, 18)
    }

    private func timestamp(_ event: SampleEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(event.date?.formatted(date: .abbreviated, time: .omitted) ?? "Undated")
            if let date = event.date, !event.dateOnly {
                Text(date.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary).monospacedDigit()
            } else if event.dateOnly && event.date != nil {
                Text("Time not recorded").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sampleLabel(_ event: SampleEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if let sample = event.aliquot {
                Button(sample.label) { details = sample }.buttonStyle(.plain).foregroundStyle(.tint).fontWeight(.semibold)
                if let variant = sample.batch?.variant, !variant.isEmpty { Text(variant).font(.caption).foregroundStyle(.secondary) }
                if sample.archived { Text("Archived").font(.caption).foregroundStyle(.secondary) }
            } else { Text("Unknown sample").foregroundStyle(.secondary) }
        }
    }

    private func activity(_ event: SampleEvent) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(event.activityTitle(concentrationUnit: concentrationUnit)).fontWeight(.medium)
            if !event.notes.isEmpty { Text(event.notes).foregroundStyle(.secondary) }
            if !event.experiment.isEmpty { Label(event.experiment, systemImage: "flask").font(.callout).foregroundStyle(.secondary) }
            if let location = event.newLocation, !location.isEmpty { Label(location, systemImage: "mappin.and.ellipse").font(.callout).foregroundStyle(.secondary) }
            if !event.wells.isEmpty { Text("Wells: \(event.wells)").font(.callout).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}
