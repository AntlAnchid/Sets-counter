import SwiftUI
import UIKit

struct HistoryTab: View {
    @EnvironmentObject var m: WorkoutManager
    @State private var message: String?
    @State private var confirmRestore = false

    private var records: [WorkoutRecord] { m.history.sorted { $0.date > $1.date } }

    var body: some View {
        NavigationStack {
            List {
                Section("Резервна копія") {
                    Button {
                        UIPasteboard.general.string = m.exportBackup()
                        message = "Скопійовано: розклад і \(m.history.count) тренувань."
                    } label: { Label("Скопіювати всі дані", systemImage: "doc.on.doc") }

                    Button { confirmRestore = true } label: {
                        Label("Відновити дані", systemImage: "square.and.arrow.down")
                    }
                }
                Section("Завершені тренування") {
                    if m.history.isEmpty { Text("Поки порожньо").foregroundStyle(.secondary) }
                    ForEach(records) { rec in
                        NavigationLink(value: rec.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(rec.dayTitle).font(.headline)
                                Text("\(Fmt.date(rec.date)) · \(rec.sets.count) підх.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offs in m.deleteRecords(offs.map { records[$0].id }) }
                }
            }
            .navigationTitle("Історія")
            .navigationDestination(for: UUID.self) { id in HistoryDetail(recordID: id) }
            .confirmationDialog("Замінити поточні розклад та історію даними з буфера обміну?",
                                isPresented: $confirmRestore, titleVisibility: .visible) {
                Button("Відновити", role: .destructive) {
                    if let text = UIPasteboard.general.string, m.importBackup(text) {
                        message = "Відновлено: \(m.history.count) тренувань."
                    } else {
                        message = "У буфері обміну немає коректних даних."
                    }
                }
                Button("Скасувати", role: .cancel) {}
            }
            .alert("Готово", isPresented: Binding(get: { message != nil },
                                                  set: { if !$0 { message = nil } })) {
                Button("OK") {}
            } message: { Text(message ?? "") }
        }
    }
}

struct HistoryDetail: View {
    @EnvironmentObject var m: WorkoutManager
    @Environment(\.dismiss) private var dismiss
    let recordID: UUID
    @State private var confirmDelete = false

    private var record: WorkoutRecord? { m.history.first { $0.id == recordID } }

    var body: some View {
        if let rec = record {
            List {
                Section {
                    DatePicker("Дата", selection: Binding(get: { rec.date },
                                                          set: { m.setDate(recordID, $0) }))
                }
                ForEach(rec.exerciseNames, id: \.self) { name in
                    let sets = rec.sets.filter { $0.exercise == name }
                    Section(name) {
                        ForEach(Array(sets.enumerated()), id: \.element.id) { i, set in
                            HStack {
                                Text("\(i + 1)").foregroundStyle(.secondary).frame(width: 22)
                                TextField("кг", text: Binding(get: { set.weight },
                                                              set: { m.updateSet(recordID, set.id, weight: $0) }))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                Text("кг").foregroundStyle(.secondary)
                                Spacer()
                                Stepper("\(set.reps) повт.",
                                        value: Binding(get: { set.reps },
                                                       set: { m.updateSet(recordID, set.id, reps: $0) }),
                                        in: 0...300)
                            }
                        }
                        .onDelete { offs in m.deleteSets(recordID, ids: offs.map { sets[$0].id }) }
                        Button { m.addSet(toRecord: recordID, exercise: name) } label: {
                            Label("Додати підхід", systemImage: "plus")
                        }
                    }
                }
                Section {
                    Button("Видалити це тренування", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(rec.dayTitle)
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("Видалити це тренування?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Видалити", role: .destructive) {
                    m.deleteRecords([recordID])
                    dismiss()
                }
                Button("Скасувати", role: .cancel) {}
            }
        } else {
            Text("Тренування видалено").foregroundStyle(.secondary)
        }
    }
}
