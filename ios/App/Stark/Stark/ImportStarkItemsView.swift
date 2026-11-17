// ios/App/Stark/Stark/ImportStarkItemsView.swift
import SwiftUI
import StarkKit

/// Settings > "Import Stark's own items" (phase 2): scan on open, preview, confirm, progress,
/// result. Every decision is `ImportModel`'s (StarkKit); this only renders its state.
struct ImportStarkItemsView: View {
    @Environment(ImportModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            switch model.state {
            case .idle, .scanning:
                scanningSection
            case .failed(let message):
                failedSection(message)
            case .preview(let plan, let destinations):
                previewSections(plan, destinations)
            case .running(let done, let total):
                runningSection(done: done, total: total)
            case .finished(let result):
                resultSections(result)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Colors.background)
        .listRowSeparatorTint(Colors.separator)
        .navigationTitle("Import")
        .navigationBarTitleDisplayMode(.inline)
        // A run is never left behind a popped screen; Stop ends it after the current item.
        .navigationBarBackButtonHidden(model.isRunning)
        .task {
            if !model.isRunning { await model.scan() }
        }
        .onDisappear {
            if !model.isRunning { model.cancel() }
        }
    }

    // MARK: States

    private var scanningSection: some View {
        Section {
            HStack(spacing: Spacing.sm) {
                ProgressView()
                Text("Reading Stark's files…").foregroundStyle(Colors.textSecondary)
            }
        }
        .listRowBackground(Colors.card)
    }

    private func failedSection(_ message: String) -> some View {
        Section {
            Text(message).foregroundStyle(Colors.yearRed)
            Button("Try Again") { Task { await model.scan() } }
                .foregroundStyle(Colors.accent)
        } footer: {
            Text("Nothing was imported. Stark never imports from files it could only partly read.")
                .foregroundStyle(Colors.textSecondary)
        }
        .listRowBackground(Colors.card)
    }

    @ViewBuilder
    private func previewSections(_ plan: ImportPlan, _ destinations: ImportDestinations) -> some View {
        Section {
            Text("Copies the items Stark keeps in its own files into Apple Calendar and Reminders, once.")
                .foregroundStyle(Colors.text)
        } footer: {
            Text("Stark's .ics files stay on this iPhone as a backup. To undo, delete the items in Apple's Calendar and Reminders apps.")
                .foregroundStyle(Colors.textSecondary)
        }
        .listRowBackground(Colors.card)

        if plan.isEmpty {
            Section {
                Text("Nothing to import. Every item Stark can move is already in Apple.")
                    .foregroundStyle(Colors.text)
            }
            .listRowBackground(Colors.card)
        } else {
            destinationSection(destinations)
            countSection(plan)
            if plan.probableDuplicates > 0 {
                Section {
                    LabeledContent("Look already in Apple") { Text("\(plan.probableDuplicates)") }
                } footer: {
                    Text("Same title and time as an item already in Apple. They are imported anyway; delete any extra copy in Apple's apps afterwards.")
                        .foregroundStyle(Colors.textSecondary)
                }
                .listRowBackground(Colors.card)
            }
            titleSection("Skips short months in Apple", plan.shortMonthRepeats,
                         footer: "Apple skips months that lack the day (Stark used the month's last day).")
        }
        titleSection("Finished series, kept in the .ics backup", plan.finishedSeries,
                     footer: "Repeating reminders with nothing left to do are not imported.")
        unrepresentableSection(plan.unrepresentable)

        if !plan.isEmpty {
            Section {
                Button {
                    Task { await model.confirm() }
                } label: {
                    Text("Import \(plan.steps.count) \(plan.steps.count == 1 ? "item" : "items")")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .foregroundStyle(destinations.problem == nil ? Colors.accent : Colors.textSecondary)
                .disabled(destinations.problem != nil || model.isRunning)
            }
            .listRowBackground(Colors.card)
        }
    }

    private func destinationSection(_ destinations: ImportDestinations) -> some View {
        Section {
            LabeledContent("Events") { Text(destinationText(destinations.calendar)) }
            LabeledContent("Reminders") { Text(destinationText(destinations.list)) }
        } header: {
            Text("Destination")
        } footer: {
            if let problem = destinations.problem {
                Text(problem).foregroundStyle(Colors.yearRed)
            } else {
                Text("Change these in Settings > Apple Calendar and Reminders.")
                    .foregroundStyle(Colors.textSecondary)
            }
        }
        .listRowBackground(Colors.card)
    }

    private func countSection(_ plan: ImportPlan) -> some View {
        Section {
            countRow("Events", plan.counts.events)
            countRow("Open reminders", plan.counts.openReminders)
            countRow("Completed reminders", plan.counts.completedReminders)
            countRow("Repeating series", plan.counts.recurringMasters)
            countRow("Plan blocks", plan.counts.planBlocks)
            countRow("Attended and skipped marks", plan.counts.outcomes)
        } header: {
            Text("What will be imported")
        } footer: {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if plan.skippedHistoryCount > 0 {
                    Text("\(plan.skippedHistoryCount) completed occurrences of repeating reminders are history and stay in the backup.")
                }
                Text("A repeating reminder starts at the occurrence Stark shows today. Occurrences you skipped after that date reappear in Apple.")
            }
            .foregroundStyle(Colors.textSecondary)
        }
        .listRowBackground(Colors.card)
    }

    private func runningSection(done: Int, total: Int) -> some View {
        Section {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(Colors.accent)
                Text("Importing \(done) of \(total)…")
                    .font(Font.footnote.monospacedDigit())
                    .foregroundStyle(Colors.textSecondary)
            }
            .padding(.vertical, Spacing.xs)
            Button("Stop") { model.cancel() }
                .foregroundStyle(Colors.accent)
        } footer: {
            Text("Stop ends the import after the current item. Opening this screen again imports the rest.")
                .foregroundStyle(Colors.textSecondary)
        }
        .listRowBackground(Colors.card)
    }

    @ViewBuilder
    private func resultSections(_ result: ImportResult) -> some View {
        Section {
            Text(summary(result)).foregroundStyle(Colors.text)
            if let stopped = result.stoppedBecauseSidecar {
                Text(stopped).foregroundStyle(Colors.yearRed)
            }
        } footer: {
            Text("Stark's .ics files stay on this iPhone as a backup. To undo, delete the items in Apple's Calendar and Reminders apps.")
                .foregroundStyle(Colors.textSecondary)
        }
        .listRowBackground(Colors.card)

        if !result.failed.isEmpty {
            Section {
                ForEach(Array(result.failed.enumerated()), id: \.offset) { _, failure in
                    titleWithReason(failure.title, failure.message)
                }
            } header: {
                Text("Not imported this time")
            } footer: {
                Text("Try again to import only these.").foregroundStyle(Colors.textSecondary)
            }
            .listRowBackground(Colors.card)
        }
        titleSection("Check these: occurrences you removed may reappear", result.needsCheck,
                     footer: "The series is in Apple Calendar, but some occurrences you had removed in Stark could not be removed there.")
        if let plan = model.lastPlan {
            unrepresentableSection(plan.unrepresentable)
        }

        Section {
            if !result.failed.isEmpty || result.cancelled || result.stoppedBecauseSidecar != nil {
                Button("Try Again") { Task { await model.scan() } }
                    .foregroundStyle(Colors.accent)
            }
            Button("Done") { dismiss() }
                .foregroundStyle(Colors.accent)
        }
        .listRowBackground(Colors.card)
    }

    // MARK: Pieces

    @ViewBuilder
    private func unrepresentableSection(_ items: [(localID: String, title: String, reason: String)]) -> some View {
        if !items.isEmpty {
            Section {
                ForEach(items, id: \.localID) { item in
                    titleWithReason(item.title, item.reason)
                }
            } header: {
                Text("Can't be imported")
            } footer: {
                Text("These stay in Stark's own files, marked \"Not imported\" in the agenda.")
                    .foregroundStyle(Colors.textSecondary)
            }
            .listRowBackground(Colors.card)
        }
    }

    @ViewBuilder
    private func titleSection(_ header: String, _ titles: [String], footer: String) -> some View {
        if !titles.isEmpty {
            Section {
                ForEach(Array(titles.enumerated()), id: \.offset) { _, title in
                    Text(title).foregroundStyle(Colors.text)
                }
            } header: {
                Text(header)
            } footer: {
                Text(footer).foregroundStyle(Colors.textSecondary)
            }
            .listRowBackground(Colors.card)
        }
    }

    private func titleWithReason(_ title: String, _ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(Colors.text)
            Text(reason).font(.footnote).foregroundStyle(Colors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func countRow(_ label: String, _ value: Int) -> some View {
        LabeledContent(label) {
            Text("\(value)").monospacedDigit()
        }
        .foregroundStyle(Colors.text)
    }

    private func destinationText(_ info: AppleCalendarInfo?) -> String {
        guard let info else { return "None" }
        return info.accountName.isEmpty ? info.title : "\(info.title) · \(info.accountName)"
    }

    private func summary(_ result: ImportResult) -> String {
        let count = result.imported.count
        var text = "Imported \(count) \(count == 1 ? "item" : "items") into Apple."
        if result.cancelled { text += " Stopped before the end." }
        return text
    }
}
