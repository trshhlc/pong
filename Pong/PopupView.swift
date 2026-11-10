//
//  PopupView.swift
//  Pong
//
//  Содержимое окна: страница таймера и страница помодоро.
//  Страницы сменяют друг друга сдвигом вбок.
//
//  Раскладка таймера: линейка сверху, под ней второстепенные кнопки,
//  внизу слева главная кнопка, справа крупные тонкие цифры.
//  Кнопки — просто слова без подложки.
//

import SwiftUI

struct PopupView: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var presence: PopupPresence
    let ruler: RulerController
    let actions: PopupActions

    var body: some View {
        ZStack {
            switch presence.page {
            case .timer:
                TimerPage(model: model, ruler: ruler, actions: actions)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .pomodoro:
                PomodoroPage(model: model, settings: model.pomodoro, actions: actions)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .buttonStyle(PongButtonStyle())
        .frame(width: Metrics.popupSize.width, height: Metrics.popupSize.height)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.popupCorner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.popupCorner, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Таймер

struct TimerPage: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var ruler: RulerController
    let actions: PopupActions

    /// Что показывают большие цифры: значение под пальцем, выбранное время или остаток
    private var shownSeconds: Int {
        if let value = ruler.liveValue { return value * model.rulerUnit.step }
        return model.isActive ? model.remaining : model.selectedValue * model.unit.step
    }

    private var primaryTitle: String {
        switch model.state {
        case .idle: "start"
        case .running: "pause"
        case .paused: "resume"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MinuteRuler(ruler: ruler, model: model)

            HStack {
                // Отменить можно сразу, даже пока мяч ещё улетает с ракетки
                Button("cancel", action: actions.cancel)
                    .disabled(!model.isActive)
                Spacer()
                Button("pomodoro", action: actions.openPomodoro)
            }
            .overlay {
                // Минуты или секунды выбираются до старта, пока время не пошло
                UnitSwitch(unit: model.rulerUnit) {
                    Haptics.tick()
                    withAnimation(Motion.snappy) {
                        model.unit = model.unit == .minutes ? .seconds : .minutes
                    }
                }
                .disabled(model.isActive || model.isServing)
            }
            .padding(.top, 10)

            Spacer(minLength: 0)

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    if model.mode == .pomodoro && model.isActive {
                        CycleDots(total: model.pomodoro.cycles, cycle: model.cycle, phase: model.phase)
                            .transition(.opacity)
                    }
                    status
                    Button(primaryTitle, action: actions.primary)
                }
                Spacer(minLength: 0)
                bigTime
            }
        }
        .padding(Metrics.popupPadding)
    }

    /// Крупные тонкие цифры. После часа шрифт поменьше, чтобы влезли часы
    private var bigTime: some View {
        Text(TimeFormat.clock(shownSeconds))
            .font(.system(size: shownSeconds >= 3600 ? 44 : 54, weight: .light, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(model.state == .paused ? Color.secondary : Color.primary)
            .contentTransition(.numericText(value: Double(shownSeconds)))
            .animation(Motion.snappy, value: shownSeconds)
            .lineLimit(1)
            .fixedSize()
    }

    /// Фаза и во сколько закончится. Пока таймер стоит, пересчитывается раз в минуту
    private var status: some View {
        TimelineView(.everyMinute) { context in
            Text(statusText(now: context.date))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func statusText(now: Date) -> String {
        if model.state == .paused { return "paused" }

        let end = model.isActive
            ? (model.endDate ?? now)
            : now.addingTimeInterval(TimeInterval(shownSeconds))
        let until = "ends at \(end.formatted(date: .omitted, time: .shortened))"

        guard model.mode == .pomodoro && model.isActive else { return until }
        return (model.phase == .work ? "work · " : "break · ") + until
    }
}

/// Цена деления линейки: минуты или секунды. Выбранное слово ярче, клик переключает
struct UnitSwitch: View {
    let unit: TimerModel.RulerUnit
    let toggle: @MainActor () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Text("min").opacity(unit == .minutes ? 1 : 0.35)
                Text("sec").opacity(unit == .seconds ? 1 : 0.35)
            }
        }
        .animation(.easeOut(duration: 0.15), value: unit)
    }
}

/// Точки циклов помодоро: пройденные — красные, текущий — бледно-красный
struct CycleDots: View {
    let total: Int
    let cycle: Int
    let phase: TimerModel.Phase

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...max(total, 1), id: \.self) { index in
                Circle()
                    .fill(color(for: index))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func color(for index: Int) -> Color {
        if index < cycle || (index == cycle && phase == .rest) { return Theme.accent }
        if index == cycle { return Theme.accent.opacity(0.45) }
        return Color.primary.opacity(0.15)
    }
}

// MARK: - Помодоро

struct PomodoroPage: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var settings: PomodoroSettings
    let actions: PopupActions

    private var startTitle: String {
        model.mode == .pomodoro && model.isActive ? "restart" : "start"
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: actions.back) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("pomodoro")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 2) {
                SettingRow(title: "cycles", value: $settings.cycles, range: PomodoroSettings.cyclesRange, unit: nil)
                Divider()
                SettingRow(title: "work", value: $settings.workMinutes, range: PomodoroSettings.workRange, unit: "min")
                Divider()
                SettingRow(title: "break", value: $settings.restMinutes, range: PomodoroSettings.restRange, unit: "min")
            }

            Spacer(minLength: 0)

            HStack(alignment: .firstTextBaseline) {
                Text("total \(TimeFormat.duration(minutes: settings.totalMinutes))")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(settings.totalMinutes)))
                    .animation(Motion.snappy, value: settings.totalMinutes)
                Spacer()
                Button(startTitle, action: actions.startPomodoro)
            }
        }
        .padding(Metrics.popupPadding)
    }
}

/// Строка настройки: название, минус, число, плюс. Кнопки повторяют нажатие, если их держать
struct SettingRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
            Spacer()
            stepButton("minus", delta: -1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(value)))
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 58)
            stepButton("plus", delta: 1)
        }
        .frame(height: 30)
        .animation(Motion.snappy, value: value)
    }

    private func stepButton(_ icon: String, delta: Int) -> some View {
        Button {
            value = (value + delta).clamped(to: range)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 24)
        }
        .buttonRepeatBehavior(.enabled)
        .disabled(delta < 0 ? value <= range.lowerBound : value >= range.upperBound)
    }
}

// MARK: - Кнопки

/// Кнопка-слово без подложки. Наведение приглушает, нажатие приглушает сильнее и чуть сжимает
struct PongButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PongButtonBody(configuration: configuration)
    }
}

private struct PongButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var opacity: Double {
        if !isEnabled { return 0.3 }
        if configuration.isPressed { return 0.45 }
        return hovering ? 0.7 : 1
    }

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(Color.primary)
            .contentShape(Rectangle())
            .opacity(opacity)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(Motion.snappy, value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
