import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

@main
struct SetsWidgets: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        StartWorkoutControl()
    }
}

struct StartWorkoutControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "StartWorkoutControl") {
            ControlWidgetButton(action: StartWorkoutIntent()) {
                Label("Тренування", systemImage: "dumbbell.fill")
            }
        }
        .displayName("Почати тренування")
        .description("Запускає Dynamic Island для підрахунку підходів")
    }
}

struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutAttributes.self) { context in
            LockScreenView(title: context.attributes.dayTitle, s: context.state, stale: context.isStale)
        } dynamicIsland: { context in
            let s = context.state
            let celebrating = s.celebration != nil && !context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if !celebrating {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.exercise).font(.headline).lineLimit(1)
                            Text(s.weight).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !celebrating {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(s.setLabel).font(.title3.bold()).monospacedDigit()
                            RestTimer(start: s.restStart)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if celebrating, let c = s.celebration {
                        CelebrationCard(text: c)
                    } else {
                        ControlsRow(s: s)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                Text("\(s.reps)").monospacedDigit()
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
        }
    }
}

struct LockScreenView: View {
    let title: String
    let s: WorkoutAttributes.ContentState
    let stale: Bool
    var body: some View {
        if let c = s.celebration, !stale {
            CelebrationCard(text: c).padding()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(s.exercise).font(.headline)
                        Text("\(title) · \(s.weight)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(s.setLabel).font(.title2.bold()).monospacedDigit()
                        RestTimer(start: s.restStart)
                    }
                }
                ControlsRow(s: s)
            }
            .padding()
        }
    }
}

/// Невеликий сірий таймер відпочинку: рахує від моменту останньої ✓.
struct RestTimer: View {
    let start: Date?
    var body: some View {
        if let start {
            Text(start, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.gray)
                .multilineTextAlignment(.trailing)
                .frame(width: 56, alignment: .trailing)
        } else {
            Text("підхід").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct CelebrationCard: View {
    let text: String
    var body: some View {
        let parts = text.components(separatedBy: "\n")
        VStack(spacing: 2) {
            Text(parts[0])
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.5)
            if parts.count > 1 {
                Text(parts[1])
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(Color.orange, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct ControlsRow: View {
    let s: WorkoutAttributes.ContentState
    var body: some View {
        if s.finished {
            Text("Готово ✓ Тренування збережено").font(.subheadline.bold())
        } else if s.hasPending {
            HStack(spacing: 6) {
                IconButton(intent: ToggleModeIntent(), icon: "arrow.left.arrow.right",
                           tint: s.weightMode ? .cyan : .gray, size: 34)
                IconButton(intent: AdjustIntent(delta: -1), icon: "minus", tint: .gray)
                VStack(spacing: 0) {
                    Text(s.weightMode ? s.weightValue : "\(s.reps)")
                        .font(.system(size: s.weightMode ? 24 : 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(s.weightMode ? Color.cyan : Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if s.weightMode {
                        Text("кг").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 50)
                IconButton(intent: AdjustIntent(delta: 1), icon: "plus", tint: .gray)
                Spacer(minLength: 4)
                IconButton(intent: SaveSetIntent(), icon: "checkmark", tint: .green)
                NextButton(s: s)
            }
        } else {
            // усі заплановані підходи виконано
            HStack(spacing: 8) {
                IconButton(intent: AddSetIntent(), icon: "plus", tint: .orange)
                Text("Підходи виконано").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                NextButton(s: s)
            }
        }
    }
}

struct NextButton: View {
    let s: WorkoutAttributes.ContentState
    var body: some View {
        IconButton(intent: NextExerciseIntent(),
                   icon: s.isLast ? "flag.checkered" : "forward.fill",
                   tint: s.isLast ? .purple : .blue)
    }
}

struct IconButton<I: AppIntent>: View {
    let intent: I
    let icon: String
    let tint: Color
    var size: CGFloat = 44
    var body: some View {
        Button(intent: intent) {
            Image(systemName: icon)
                .font(.system(size: size * 0.41, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(tint.opacity(0.85), in: Circle())
        }
        .buttonStyle(.plain)
    }
}
