//
//  MinuteRuler.swift
//  Pong
//
//  Линейка. Отметки едут под неподвижным красным указателем.
//  Одно деление — минута или секунда, смотря что выбрано (TimerModel.rulerUnit).
//  Тянешь мышью или свайпаешь трекпадом — значение идёт за пальцем без анимации,
//  отпускаешь — линейка докатывается по инерции и пружиной встаёт на целое деление.
//  Пока таймер идёт, линейка показывает остаток, и её можно подвинуть.
//

import AppKit
import SwiftUI

@MainActor
final class RulerController: ObservableObject {
    /// Значение под пальцем, пока линейку тянут. nil — линейка показывает таймер
    @Published private(set) var live: Double?

    private let model: TimerModel
    /// Значение в момент, когда начали тянуть
    private var anchor: Double = 0
    /// Значение без «резинки» на краях
    private var raw: Double = 0
    /// Последнее целое деление, на котором щёлкнул трекпад
    private var lastWhole = 0
    /// Скорость свайпа, делений в секунду
    private var scrollVelocity: Double = 0
    private var lastScrollTime: TimeInterval = 0

    /// Насколько далеко докатывается линейка после броска
    private let flickFactor = 0.6

    init(model: TimerModel) {
        self.model = model
    }

    /// Целое деление под указателем, пока линейку тянут
    var liveValue: Int? {
        live.map { Int($0.rounded()).clamped(to: TimerModel.rulerRange) }
    }

    // MARK: - Мышь

    func dragChanged(translation: CGFloat) {
        if live == nil { begin() }
        set(anchor - Double(translation / Metrics.tickSpacing))
    }

    /// predicted — куда бы долетел палец по инерции, его даёт DragGesture
    func dragEnded(translation: CGFloat, predicted: CGFloat) {
        let flick = Double((predicted - translation) / Metrics.tickSpacing) * flickFactor
        commit(toward: raw - flick)
    }

    // MARK: - Трекпад и колесо

    func scroll(_ event: NSEvent) {
        // Колесо мыши: щелчок колеса — одно деление
        guard event.hasPreciseScrollingDeltas else {
            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.scrollingDeltaX
            if delta != 0 { step(by: delta > 0 ? -1 : 1) }
            return
        }

        // Системную инерцию пропускаем: докатываем сами, чтобы встать ровно на деление
        guard event.momentumPhase.isEmpty else { return }

        let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
        let delta = abs(dx) >= abs(dy) ? dx : dy

        if event.phase.contains(.began) {
            begin()
            scrollVelocity = 0
            lastScrollTime = event.timestamp
        }

        if event.phase.contains(.changed) {
            if live == nil { begin() }
            let change = -Double(delta / Metrics.tickSpacing)
            let dt = event.timestamp - lastScrollTime
            if dt > 0 { scrollVelocity = scrollVelocity * 0.6 + change / dt * 0.4 }
            lastScrollTime = event.timestamp
            set(raw + change)
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            commit(toward: raw + scrollVelocity * 0.12 * flickFactor)
        }
    }

    /// На деление вперёд или назад: клавиши-стрелки и колесо мыши
    func step(by steps: Int) {
        let base = liveValue ?? Int(model.rulerValue.rounded())
        let next = (base + steps).clamped(to: TimerModel.rulerRange)
        guard next != base || live != nil else { return }
        Haptics.tick()
        withAnimation(Motion.snappy) {
            model.setRulerValue(next)
            live = nil
        }
    }

    // MARK: - Общее

    private func begin() {
        anchor = model.rulerValue
        raw = anchor
        lastWhole = Int(anchor.rounded())
        live = anchor
    }

    private func set(_ value: Double) {
        raw = value
        let low = Double(TimerModel.rulerRange.lowerBound)
        let high = Double(TimerModel.rulerRange.upperBound)

        // За краями линейка тянется как резинка и не уходит далеко
        var shown = value
        if value < low { shown = low - rubber(low - value) }
        if value > high { shown = high + rubber(value - high) }
        live = shown

        // Лёгкий щелчок трекпада на каждом делении
        let whole = Int(shown.rounded()).clamped(to: TimerModel.rulerRange)
        if whole != lastWhole {
            lastWhole = whole
            Haptics.tick()
        }
    }

    private func rubber(_ overshoot: Double) -> Double {
        overshoot * 0.3 / (1 + overshoot * 0.08)
    }

    /// Отпустили: встаём на ближайшее целое деление одной пружиной
    private func commit(toward target: Double) {
        guard live != nil else { return }
        let value = Int(target.rounded()).clamped(to: TimerModel.rulerRange)
        withAnimation(Motion.snappy) {
            model.setRulerValue(value)
            live = nil
        }
    }
}

struct MinuteRuler: View {
    @ObservedObject var ruler: RulerController
    @ObservedObject var model: TimerModel

    var body: some View {
        let value = ruler.live ?? model.rulerValue

        ZStack(alignment: .topLeading) {
            RulerTicks()
                .frame(width: Metrics.rulerStripWidth, height: Metrics.rulerHeight)
                .offset(x: Metrics.rulerWidth / 2 - Metrics.rulerLead - CGFloat(value) * Metrics.tickSpacing)
                // Смена цены деления (минуты ↔ секунды) — пружиной: в последнюю минуту
                // линейка перескакивает с 1 на 59, а после конца возвращается к минутам
                .animation(Motion.spring, value: model.rulerUnit)
                // Каждую секунду линейка сдвигается той же пружиной, что и цифры, а не прыжком.
                // Пока линейку тянут, без анимации: она должна идти за пальцем.
                // Этот модификатор снаружи, поэтому при смене минут на секунды побеждает пружина выше
                .animation(ruler.live == nil ? Motion.snappy : nil, value: model.remaining)
        }
        .frame(width: Metrics.rulerWidth, height: Metrics.rulerHeight, alignment: .topLeading)
        .clipped()
        .mask { edgeFade }
        .overlay(alignment: .top) { pointer }
        .contentShape(Rectangle())
        .gesture(drag)
    }

    /// Указатель — красная «ракетка», под которой едут деления
    private var pointer: some View {
        Capsule()
            .fill(Theme.accent)
            .frame(width: 4, height: 26)
            .shadow(color: Theme.accent.opacity(0.6), radius: 3)
    }

    /// Отметки растворяются к краям
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.22),
                .init(color: .black, location: 0.78),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { ruler.dragChanged(translation: $0.translation.width) }
            .onEnded {
                ruler.dragEnded(translation: $0.translation.width, predicted: $0.predictedEndTranslation.width)
            }
    }
}

/// Сами отметки. Рисуются один раз, двигается только смещение всей полосы
struct RulerTicks: View {
    var body: some View {
        Canvas { context, _ in
            for minute in 0...TimerModel.rulerRange.upperBound {
                let x = Metrics.rulerLead + CGFloat(minute) * Metrics.tickSpacing
                let major = minute % 5 == 0
                let tick = CGRect(x: x - 0.75, y: 4, width: 1.5, height: major ? 18 : 9)
                context.fill(
                    Path(roundedRect: tick, cornerRadius: 0.75),
                    with: .color(.primary.opacity(major ? 0.55 : 0.22))
                )
                if major && minute > 0 {
                    let label = Text("\(minute)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary)
                    context.draw(label, at: CGPoint(x: x, y: 34))
                }
            }
        }
    }
}

/// Отклик трекпада Force Touch. Чувствуется, только пока палец на трекпаде:
/// на мыши и с клавиатуры ничего не происходит
enum Haptics {
    /// Лёгкий щелчок на каждой минуте линейки
    @MainActor static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// Отклик на старт, паузу и отмену — плотнее щелчка линейки
    @MainActor static func tap() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
