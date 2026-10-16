import Foundation

enum Sample {
    static let schedule = """
    # 1. Груди + Біцепс
    Жим лежачи | 60 | 4 | 8-12
    Згинання на біцепс | 15 | 3 | 10
    # 2. Ноги
    Присідання | 80 | 5 | 5
    """
}

/// "# Будь-яка назва", далі "Вправа | вага | підходи | повтори" (повтори: 10 або 8-12)
enum ScheduleParser {
    static func parseReps(_ s: String) -> (Int, Int) {
        let cleaned = s.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        let nums = cleaned.split(separator: "-").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        switch nums.count {
        case 0: return (10, 10)
        case 1: return (nums[0], nums[0])
        default: return (min(nums[0], nums[1]), max(nums[0], nums[1]))
        }
    }

    static func parse(_ text: String) -> [WorkoutDay] {
        var days: [WorkoutDay] = []
        var current: WorkoutDay?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") { continue }
            if line.hasPrefix("#") {
                if let c = current, !c.exercises.isEmpty { days.append(c) }
                var title = String(line.drop(while: { $0 == "#" || $0 == " " }))
                if title.isEmpty { title = "День \(days.count + 1)" }
                current = WorkoutDay(title: title, exercises: [])
                continue
            }
            let p = line.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
            guard p.count >= 2, !p[0].isEmpty else { continue }
            let reps = p.count > 3 ? parseReps(p[3]) : (10, 10)
            let ex = Exercise(name: p[0], weight: p[1],
                              sets: max(1, p.count > 2 ? (Int(p[2]) ?? 3) : 3),
                              repsMin: reps.0, repsMax: reps.1)
            if current == nil { current = WorkoutDay(title: "Тренування", exercises: []) }
            current?.exercises.append(ex)
        }
        if let c = current, !c.exercises.isEmpty { days.append(c) }
        return days
    }
}
