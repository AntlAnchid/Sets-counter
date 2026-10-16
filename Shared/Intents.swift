import AppIntents

// LiveActivityIntent виконується в процесі ЗАСТОСУНКУ, тому App Groups не потрібні.

struct AdjustIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Змінити повтори або вагу"
    @Parameter(title: "Зміна") var delta: Int
    init() {}
    init(delta: Int) { self.delta = delta }
    func perform() async throws -> some IntentResult {
        await WorkoutManager.shared.adjust(delta)
        return .result()
    }
}

struct ToggleModeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Повтори / вага"
    init() {}
    func perform() async throws -> some IntentResult {
        await WorkoutManager.shared.toggleMode()
        return .result()
    }
}

struct SaveSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Зберегти підхід"
    init() {}
    func perform() async throws -> some IntentResult {
        await WorkoutManager.shared.saveSet()
        return .result()
    }
}

struct AddSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Додати підхід"
    init() {}
    func perform() async throws -> some IntentResult {
        await WorkoutManager.shared.addSet()
        return .result()
    }
}

struct NextExerciseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Наступна вправа"
    init() {}
    func perform() async throws -> some IntentResult {
        await WorkoutManager.shared.nextExercise()
        return .result()
    }
}

struct StartWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Почати тренування"
    static let openAppWhenRun: Bool = true
    init() {}
    func perform() async throws -> some IntentResult {
        await WorkoutManager.shared.requestStart()
        return .result()
    }
}
