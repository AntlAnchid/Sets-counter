import Foundation
import ActivityKit

// MARK: Допоміжне

enum W {
    static func value(_ s: String) -> Double? {
        var t = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        if t.hasSuffix(".") { t.removeLast() }   // "50." → 50
        return Double(t)
    }
    static func format(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
    static func label(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "" }
        if let v = value(t) { return v == 0 ? "власна вага" : "\(format(v)) кг" }
        return t
    }
    static func adjust(_ s: String, by d: Double) -> String {
        format(max(0, (value(s) ?? 0) + d))
    }

    /// Крок береться із запису ваги в РОЗКЛАДІ: є крапка ("7.5", "50.", "0.") → 2.5, інакше ("50", "0") → 2.
    static func stepRule(_ schedule: String) -> Double {
        schedule.replacingOccurrences(of: ",", with: ".").contains(".") ? 2.5 : 2
    }

    static func stepped(_ s: String, direction: Int, step: Double) -> String {
        format(max(0, (value(s) ?? 0) + (direction > 0 ? step : -step)))
    }

    static func plural(_ n: Int) -> String {
        let m10 = n % 10, m100 = n % 100
        return (1...4).contains(m10) && !(11...14).contains(m100) ? "повторення" : "повторень"
    }
}

enum Fmt {
    static let df: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "uk_UA")
        f.dateFormat = "d MMM yyyy, EEE"
        return f
    }()
    static func date(_ d: Date) -> String { df.string(from: d) }
}

// MARK: Розклад

struct Exercise: Codable, Hashable {
    var name: String
    var weight: String
    var sets: Int
    var repsMin: Int
    var repsMax: Int
    var repsText: String { repsMin == repsMax ? "\(repsMax)" : "\(repsMin)-\(repsMax)" }
}

struct WorkoutDay: Codable, Hashable {
    var title: String
    var exercises: [Exercise]
}

// MARK: Записи

struct LoggedSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var exercise: String
    var weight: String
    var reps: Int
    var time: Date
}

struct WorkoutRecord: Codable, Hashable, Identifiable {
    var id = UUID()
    var date: Date
    var dayTitle: String
    var sets: [LoggedSet]

    var exerciseNames: [String] {
        var o: [String] = []
        for s in sets where !o.contains(s.exercise) { o.append(s.exercise) }
        return o
    }
}

struct Backup: Codable {
    var version = 1
    var schedule: String
    var dayIndex: Int
    var history: [WorkoutRecord]
}

// MARK: Live Activity

struct WorkoutAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var exercise: String
        var weight: String
        var setLabel: String      // "2/4" або "5/4" для додаткових підходів
        var reps: Int
        var hasPending: Bool      // є підхід, який ще треба записати
        var restStart: Date?      // момент останньої ✓ (для таймера відпочинку)
        var isLast: Bool          // немає інших незавершених вправ
        var celebration: String?  // "Великий текст\nдрібний текст"
        var finished: Bool
        var weightMode: Bool      // кнопки −/+ змінюють вагу, а не повтори
        var weightValue: String   // робоча вага числом, без «кг»
    }
    var dayTitle: String
}

// MARK: Сесія (поточне тренування)

struct Session: Codable {
    var dayIndex: Int
    var dayTitle: String
    var exercises: [Exercise]
    var currentName: String
    var reps: Int
    var weights: [String: String] = [:]   // робоча вага на сьогодні
    var extra: [String: Int] = [:]        // додаткові підходи
    var log: [LoggedSet] = []             // усі записані підходи (зберігаються одразу)
    var startedAt = Date()
    var restStart: Date? = nil
    var weightModeStored: Bool? = nil     // Optional — щоб стара збережена сесія ще читалась
    var weightMode: Bool {
        get { weightModeStored ?? false }
        set { weightModeStored = newValue }
    }

    func index(of name: String) -> Int? { exercises.firstIndex { $0.name == name } }
    var current: Exercise { exercises.first { $0.name == currentName } ?? exercises[0] }
    func done(_ name: String) -> Int { log.filter { $0.exercise == name }.count }
    func total(_ ex: Exercise) -> Int { ex.sets + (extra[ex.name] ?? 0) }
    func hasPending(_ ex: Exercise) -> Bool { done(ex.name) < total(ex) }
    func isComplete(_ ex: Exercise) -> Bool { done(ex.name) >= total(ex) }

    /// Наступна незавершена вправа (спершу після поточної, потім з початку списку).
    func nextName() -> String? {
        guard let i = index(of: currentName) else {
            return exercises.first { !isComplete($0) }?.name
        }
        let order = Array(exercises[(i + 1)...]) + Array(exercises[..<i])
        return order.first { !isComplete($0) }?.name
    }

    func state(finished: Bool = false, celebration: String? = nil) -> WorkoutAttributes.ContentState {
        let ex = current
        let n = done(ex.name)
        let pending = hasPending(ex)
        return WorkoutAttributes.ContentState(
            exercise: ex.name,
            weight: W.label(weights[ex.name] ?? ex.weight),
            setLabel: pending ? "\(n + 1)/\(ex.sets)" : "\(n)/\(ex.sets)",
            reps: reps,
            hasPending: pending,
            restStart: restStart,
            isLast: nextName() == nil,
            celebration: celebration,
            finished: finished,
            weightMode: weightMode,
            weightValue: W.value(weights[ex.name] ?? ex.weight).map { W.format($0) } ?? "0")
    }
}
