import SwiftUI

struct WorkoutTab: View {
    @EnvironmentObject var m: WorkoutManager
    @State private var expanded: Set<String> = []
    @State private var showSchedule = false
    @State private var confirmDiscard = false

    private var previewDay: WorkoutDay? {
        m.days.indices.contains(m.dayIndex) ? m.days[m.dayIndex] : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DisclosureGroup("Розклад", isExpanded: $showSchedule) {
                        TextEditor(text: $m.scheduleText)
                            .frame(minHeight: 240)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled()
                        Text("# Будь-яка назва тренування, далі рядки:\nВправа | вага | підходи | повтори (10 або 8-12)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("День") {
                    if m.days.isEmpty {
                        Text("Вправ у розкладі не знайдено")
                    } else {
                        Picker("День", selection: $m.dayIndex) {
                            ForEach(Array(m.days.enumerated()), id: \.offset) { i, day in
                                Text(day.title).tag(i)
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(m.session != nil)
                    }
                }

                Section("Тренування") {
                    if let s = m.session {
                        ForEach(Array(s.exercises.enumerated()), id: \.offset) { _, ex in
                            ExerciseRow(ex: ex, s: s, expanded: $expanded)
                        }
                        Button { Task { await m.undoLastSet() } } label: {
                            Label("Скасувати останній підхід", systemImage: "arrow.uturn.backward")
                        }
                        .disabled(s.log.isEmpty)
                        Button { Task { await m.finish() } } label: {
                            Label("Завершити й зберегти", systemImage: "flag.checkered")
                        }
                        Button(role: .destructive) { confirmDiscard = true } label: {
                            Label("Скасувати без збереження", systemImage: "xmark.circle")
                        }
                    } else {
                        Button { Task { await m.start() } } label: {
                            Label("Почати тренування", systemImage: "play.fill")
                        }
                        if let day = previewDay {
                            ForEach(Array(day.exercises.enumerated()), id: \.offset) { _, ex in
                                ExerciseRow(ex: ex, s: nil, expanded: $expanded)
                            }
                        }
                    }
                    if let e = m.lastError { Text(e).foregroundStyle(.red) }
                    if let url = m.lastExport {
                        ShareLink(item: url) { Label("Поділитись останнім записом", systemImage: "square.and.arrow.up") }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Підходи")
            .confirmationDialog("Скасувати тренування без збереження?",
                                isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Скасувати тренування", role: .destructive) { Task { await m.discard() } }
                Button("Ні", role: .cancel) {}
            }
        }
    }
}

struct ExerciseRow: View {
    @EnvironmentObject var m: WorkoutManager
    let ex: Exercise
    let s: Session?
    @Binding var expanded: Set<String>

    private var isOpen: Bool { expanded.contains(ex.name) }
    private var isCurrent: Bool { s?.currentName == ex.name }
    private var complete: Bool { s?.isComplete(ex) ?? false }

    private var subtitle: String {
        if let s {
            let w = W.label(s.weights[ex.name] ?? ex.weight)
            return "\(w) · \(s.done(ex.name))/\(s.total(ex)) підх. · \(ex.repsText) повт."
        }
        return "\(W.label(m.plannedWeight(for: ex))) · \(ex.sets)×\(ex.repsText)"
    }

    private func toggle() {
        if isOpen { expanded.remove(ex.name) } else { expanded.insert(ex.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // тап по назві — зробити вправу активною
                Button {
                    if s != nil { Task { await m.activate(ex.name) } } else { toggle() }
                } label: {
                    HStack {
                        Image(systemName: isCurrent ? "largecircle.fill.circle"
                              : (complete ? "checkmark.circle.fill" : "circle"))
                            .foregroundStyle(isCurrent ? Color.orange : (complete ? Color.green : Color.secondary))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.headline).foregroundStyle(.primary)
                            Text(subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)

                Button { toggle() } label: {
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").padding(8)
                }
                .buttonStyle(.borderless)
            }
            if isOpen { details }
        }
    }

    @ViewBuilder private var details: some View {
        // 1) минулий раз
        VStack(alignment: .leading, spacing: 2) {
            Text("Минулого разу").font(.caption.bold()).foregroundStyle(.secondary)
            if let last = m.lastResult(for: ex.name) {
                Text(Fmt.date(last.date)).font(.caption).foregroundStyle(.secondary)
                ForEach(Array(last.sets.enumerated()), id: \.element.id) { i, set in
                    Text("\(i + 1). \(W.label(set.weight)) × \(set.reps)").font(.callout.monospacedDigit())
                }
            } else {
                Text("Ще не виконувалась").font(.callout).foregroundStyle(.secondary)
            }
        }

        if let s {
            // 2) вага
            VStack(alignment: .leading, spacing: 6) {
                Text("Робоча вага: \(W.label(s.weights[ex.name] ?? ex.weight))").font(.callout.bold())
                HStack(spacing: 8) {
                    ForEach([-5.0, -2.5, 2.5, 5.0], id: \.self) { delta in
                        Button(delta > 0 ? "+\(W.format(delta))" : "−\(W.format(-delta))") {
                            Task { await m.changeWeight(ex.name, by: delta) }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // 3) підходи сьогодні
            let sets = s.log.filter { $0.exercise == ex.name }
            VStack(alignment: .leading, spacing: 4) {
                Text("Сьогодні").font(.caption.bold()).foregroundStyle(.secondary)
                if sets.isEmpty {
                    Text("Ще немає підходів").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
                    HStack {
                        Text("\(i + 1). \(W.label(set.weight)) × \(set.reps)").font(.callout.monospacedDigit())
                        Spacer()
                        Button(role: .destructive) { Task { await m.deleteSet(set.id) } } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}
