import SwiftUI
import ActivityKit

@MainActor
final class WorkoutManager: ObservableObject {
    static let shared = WorkoutManager()
    private let d = UserDefaults.standard

    @Published var scheduleText: String {
        didSet {
            d.set(scheduleText, forKey: "schedule")
            scheduleChanged()
        }
    }
    @Published var dayIndex: Int { didSet { d.set(dayIndex, forKey: "dayIndex") } }
    @Published private(set) var days: [WorkoutDay]
    @Published private(set) var session: Session? = nil
    @Published private(set) var history: [WorkoutRecord] = [] {
        didSet { Self.storeHistory(history) }
    }
    @Published var lastExport: URL? = nil
    @Published var lastError: String? = nil
    private var lastPushed: WorkoutAttributes.ContentState? = nil

    private init() {
        let text = d.string(forKey: "schedule") ?? Sample.schedule
        let parsed = ScheduleParser.parse(text)
        scheduleText = text
        days = parsed
        dayIndex = min(max(d.integer(forKey: "dayIndex"), 0), max(parsed.count - 1, 0))
        history = Self.loadHistory()
        d.removeObject(forKey: "session") // старий формат
        if let data = d.data(forKey: "session2"),
           let s = try? JSONDecoder().decode(Session.self, from: data) {
            session = s
        }
    }

    // MARK: Сховище

    private static var historyURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("history.json")
    }
    private static func loadHistory() -> [WorkoutRecord] {
        guard let data = try? Data(contentsOf: historyURL) else { return [] }
        return (try? JSONDecoder().decode([WorkoutRecord].self, from: data)) ?? []
    }
    private static func storeHistory(_ h: [WorkoutRecord]) {
        let url = historyURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(h) { try? data.write(to: url, options: .atomic) }
    }

    /// Кожна зміна сесії одразу пишеться на диск.
    private func save(_ s: Session?) {
        session = s
        if let s, let data = try? JSONEncoder().encode(s) {
            d.set(data, forKey: "session2")
        } else {
            d.removeObject(forKey: "session2")
        }
    }

    // MARK: Пам'ять минулих тренувань

    private func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

    func lastResult(for name: String) -> (date: Date, sets: [LoggedSet])? {
        let key = norm(name)
        for rec in history.sorted(by: { $0.date > $1.date }) {
            let sets = rec.sets.filter { norm($0.exercise) == key }
            if !sets.isEmpty { return (rec.date, sets) }
        }
        return nil
    }

    /// Вага: з минулого разу, інакше з розкладу.
    func plannedWeight(for ex: Exercise) -> String {
        lastResult(for: ex.name)?.sets.last?.weight ?? ex.weight
    }

    /// Повтори: з минулого разу для цього номера підходу, інакше верхня межа діапазону.
    func suggestedReps(for ex: Exercise, setNumber: Int, fallback: Int? = nil) -> Int {
        if let last = lastResult(for: ex.name), !last.sets.isEmpty {
            return last.sets[min(max(setNumber, 1), last.sets.count) - 1].reps
        }
        return fallback ?? ex.repsMax
    }

    private func fillWeights(_ s: inout Session) {
        for ex in s.exercises where s.weights[ex.name] == nil {
            s.weights[ex.name] = plannedWeight(for: ex)
        }
    }

    // MARK: Розклад змінено посеред тренування

    private func scheduleChanged() {
        days = ScheduleParser.parse(scheduleText)
        if dayIndex >= days.count { dayIndex = max(0, days.count - 1) }
        guard var s = session, !days.isEmpty else { return }
        var day = days.first { $0.title == s.dayTitle }
        if day == nil, days.indices.contains(s.dayIndex) { day = days[s.dayIndex] }
        guard let day else { return }
        var list = day.exercises
        // вправи, що вже мають записані підходи, не зникають
        for old in s.exercises where s.done(old.name) > 0 && !list.contains(where: { $0.name == old.name }) {
            list.append(old)
        }
        s.dayTitle = day.title
        s.exercises = list
        if s.index(of: s.currentName) == nil {
            s.currentName = list[0].name
            s.reps = suggestedReps(for: list[0], setNumber: s.done(list[0].name) + 1)
        }
        fillWeights(&s)
        save(s)
        Task { await push() }
    }

    // MARK: Запуск

    func requestStart() async {
        if await start() { return }
        d.set(true, forKey: "pendingStart")
    }

    func startIfPending() async {
        guard d.bool(forKey: "pendingStart") else { return }
        d.set(false, forKey: "pendingStart")
        await start()
    }

    func refresh() async {
        if session != nil { await push(force: true) }
    }

    @discardableResult
    func start() async -> Bool {
        lastError = nil
        if session != nil, !Activity<WorkoutAttributes>.activities.isEmpty { return true }

        var s: Session
        if let existing = session {
            s = existing
        } else {
            guard !days.isEmpty else { lastError = "У розкладі немає вправ"; return false }
            let idx = min(max(dayIndex, 0), days.count - 1)
            let day = days[idx]
            s = Session(dayIndex: idx, dayTitle: day.title, exercises: day.exercises,
                        currentName: day.exercises[0].name, reps: 0)
            fillWeights(&s)
            s.reps = suggestedReps(for: s.current, setNumber: 1)
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities вимкнені в налаштуваннях"
            return false
        }
        for a in Activity<WorkoutAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        do {
            let st = s.state()
            _ = try Activity.request(attributes: WorkoutAttributes(dayTitle: s.dayTitle),
                                     content: ActivityContent(state: st, staleDate: nil))
            lastPushed = st
            save(s)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: Дії (Dynamic Island і додаток)

    /// −/+ в острові: повтори або вага (залежно від режиму ⇄).
    func adjust(_ delta: Int) async {
        guard var s = session else { return }
        let ex = s.current
        if s.weightMode {
            s.weights[ex.name] = W.stepped(s.weights[ex.name] ?? ex.weight, direction: delta)
        } else {
            guard s.hasPending(ex) else { return }
            s.reps = max(0, min(300, s.reps + delta))
        }
        save(s)
        await push()
    }

    func toggleMode() async {
        guard var s = session else { return }
        s.weightMode.toggle()
        save(s)
        await push()
    }

    func saveSet() async {
        guard var s = session else { return }
        let ex = s.current
        guard s.hasPending(ex) else { return }
        s.log.append(LoggedSet(exercise: ex.name, weight: s.weights[ex.name] ?? ex.weight,
                               reps: s.reps, time: Date()))
        s.restStart = Date()
        s.weightMode = false
        if s.hasPending(ex) {
            s.reps = suggestedReps(for: ex, setNumber: s.done(ex.name) + 1, fallback: s.reps)
        }
        save(s)
        await push()
    }

    /// Помаранчевий «+»: відкрити ще один підхід (5/4, 6/4 …).
    func addSet() async {
        guard var s = session else { return }
        let ex = s.current
        guard !s.hasPending(ex) else { return }
        s.extra[ex.name, default: 0] += 1
        s.reps = suggestedReps(for: ex, setNumber: s.done(ex.name) + 1, fallback: s.reps)
        save(s)
        await push()
    }

    func nextExercise() async {
        guard let s0 = session else { return }
        let ex = s0.current
        if s0.isComplete(ex), let msg = celebrationText(for: ex.name, in: s0) {
            await showCelebration(msg, base: s0)
        }
        guard var s = session else { return }
        if let next = s.nextName(), let nex = s.exercises.first(where: { $0.name == next }) {
            s.currentName = next
            s.weightMode = false
            s.reps = suggestedReps(for: nex, setNumber: s.done(next) + 1, fallback: nex.repsMax)
            save(s)
            await push(force: true)
        } else {
            await finish()
        }
    }

    func activate(_ name: String) async {
        guard var s = session, let ex = s.exercises.first(where: { $0.name == name }) else { return }
        s.currentName = name
        s.weightMode = false
        s.reps = suggestedReps(for: ex, setNumber: s.done(name) + 1, fallback: ex.repsMax)
        save(s)
        await push()
    }

    func changeWeight(_ name: String, by delta: Double) async {
        guard var s = session else { return }
        s.weights[name] = W.adjust(s.weights[name] ?? "", by: delta)
        save(s)
        await push()
    }

    func deleteSet(_ id: UUID) async {
        guard var s = session else { return }
        s.log.removeAll { $0.id == id }
        save(s)
        await push()
    }

    /// Скасувати останній записаний підхід (якщо випадково натиснули ✓).
    func undoLastSet() async {
        guard var s = session, let last = s.log.last else { return }
        s.log.removeLast()
        if s.index(of: last.exercise) != nil { s.currentName = last.exercise }
        s.reps = last.reps
        s.restStart = s.log.last?.time
        save(s)
        await push()
    }

    func finish() async {
        guard let s = session else { return }
        let saved = !s.log.isEmpty
        if saved {
            let rec = WorkoutRecord(date: s.startedAt, dayTitle: s.dayTitle, sets: s.log)
            history.append(rec)
            lastExport = Exporter.write(rec)
            if !days.isEmpty { dayIndex = (s.dayIndex + 1) % days.count } // наступний день по колу
        }
        let content = ActivityContent(state: s.state(finished: true), staleDate: nil)
        for a in Activity<WorkoutAttributes>.activities {
            await a.end(content, dismissalPolicy: saved ? .after(Date().addingTimeInterval(60)) : .immediate)
        }
        lastPushed = nil
        save(nil)
    }

    func discard() async {
        for a in Activity<WorkoutAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
        lastPushed = nil
        save(nil)
    }

    // MARK: Мотивація

    private func celebrationText(for name: String, in s: Session) -> String? {
        let today = s.log.filter { $0.exercise == name }
        guard !today.isEmpty else { return nil }
        guard let last = lastResult(for: name) else {
            return "Вправу завершено ✓\nПерший запис — є з чим порівнювати"
        }
        let wToday = today.compactMap { W.value($0.weight) }.max()
        let wLast = last.sets.compactMap { W.value($0.weight) }.max()
        let diff = today.reduce(0) { $0 + $1.reps } - last.sets.reduce(0) { $0 + $1.reps }
        if let a = wToday, let b = wLast, a > b {
            var sub = "робоча вага зросла"
            if diff > 0 { sub += " · +\(diff) \(W.plural(diff))" }
            return "+\(W.format(a - b)) кг\n\(sub)"
        }
        if let a = wToday, let b = wLast, a < b {
            return "Вправу завершено ✓\nминулого разу вага була \(W.format(b)) кг"
        }
        if diff > 0 { return "+\(diff) \(W.plural(diff))\nу сумі більше, ніж минулого разу" }
        if diff == 0 { return "Стабільно 💪\nстільки ж, як минулого разу" }
        return "Вправу завершено ✓\nминулого разу було на \(-diff) \(W.plural(-diff)) більше"
    }

    private func showCelebration(_ text: String, base s: Session) async {
        // staleDate: якщо процес раптом помре, острів сам перестане показувати екран мотивації
        let content = ActivityContent(state: s.state(celebration: text),
                                      staleDate: Date().addingTimeInterval(4))
        for a in Activity<WorkoutAttributes>.activities { await a.update(content) }
        try? await Task.sleep(nanoseconds: 2_600_000_000)
        lastPushed = nil
    }

    private func push(force: Bool = false) async {
        guard let s = session else { return }
        let st = s.state()
        if !force, st == lastPushed { return }
        lastPushed = st
        let content = ActivityContent(state: st, staleDate: nil)
        for a in Activity<WorkoutAttributes>.activities { await a.update(content) }
    }

    // MARK: Історія

    func deleteRecords(_ ids: [UUID]) { history.removeAll { ids.contains($0.id) } }

    func setDate(_ rid: UUID, _ date: Date) {
        guard let i = history.firstIndex(where: { $0.id == rid }) else { return }
        history[i].date = date
    }

    func updateSet(_ rid: UUID, _ sid: UUID, weight: String? = nil, reps: Int? = nil) {
        guard let i = history.firstIndex(where: { $0.id == rid }),
              let j = history[i].sets.firstIndex(where: { $0.id == sid }) else { return }
        if let weight { history[i].sets[j].weight = weight }
        if let reps { history[i].sets[j].reps = reps }
    }

    func deleteSets(_ rid: UUID, ids: [UUID]) {
        guard let i = history.firstIndex(where: { $0.id == rid }) else { return }
        history[i].sets.removeAll { ids.contains($0.id) }
    }

    func addSet(toRecord rid: UUID, exercise: String) {
        guard let i = history.firstIndex(where: { $0.id == rid }) else { return }
        let prev = history[i].sets.last { $0.exercise == exercise }
        let new = LoggedSet(exercise: exercise, weight: prev?.weight ?? "", reps: prev?.reps ?? 10, time: Date())
        if let k = history[i].sets.lastIndex(where: { $0.exercise == exercise }) {
            history[i].sets.insert(new, at: k + 1)
        } else {
            history[i].sets.append(new)
        }
    }

    // MARK: Резервна копія

    func exportBackup() -> String {
        let b = Backup(schedule: scheduleText, dayIndex: dayIndex, history: history)
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? e.encode(b) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    func importBackup(_ text: String) -> Bool {
        guard let a = text.firstIndex(of: "{"), let z = text.lastIndex(of: "}"), a < z else { return false }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let b = try? dec.decode(Backup.self, from: Data(String(text[a...z]).utf8)) else { return false }
        scheduleText = b.schedule
        dayIndex = min(max(b.dayIndex, 0), max(days.count - 1, 0))
        history = b.history
        return true
    }
}
