//
//  TimerModel.swift
//  Pong
//
//  Таймер и помодоро. Хранит не «сколько секунд осталось», а момент окончания:
//  так время не сбивается, если Mac уснул или приложение было занято.
//

import Foundation

@MainActor
final class TimerModel: ObservableObject {
    enum Mode { case timer, pomodoro }
    enum Phase { case work, rest }
    enum State { case idle, running, paused }

    /// Что случилось: подача или фаза дошла до нуля. По нему играет звук и приходит уведомление
    enum Event {
        /// Ракетка ударила по мячу перед стартом. Только звук, без уведомления
        case serve
        case timerFinished
        case workFinished(cycle: Int, of: Int, restMinutes: Int)
        case restFinished(nextCycle: Int, of: Int, workMinutes: Int)
        case pomodoroFinished(cycles: Int)
    }

    /// В чём выставляется обычный таймер: в минутах или в секундах
    enum RulerUnit: String {
        case minutes, seconds

        /// Сколько секунд в одном делении линейки
        var step: Int { self == .minutes ? 60 : 1 }
    }

    /// Деления линейки. Одинаковые для минут и секунд, меняется только цена деления
    nonisolated static let rulerRange = 1...120

    @Published private(set) var state: State = .idle {
        didSet { updateActivity() }
    }
    @Published private(set) var mode: Mode = .timer
    @Published private(set) var phase: Phase = .work
    /// Текущий цикл помодоро, с единицы
    @Published private(set) var cycle = 1
    /// Сколько секунд осталось в текущей фазе
    @Published private(set) var remaining = 0
    /// Идёт подача: мяч улетает с ракетки. Время уже идёт, но трей ещё показывает ракетку
    /// и раскроется в капсулу, когда подача закончится
    @Published private(set) var isServing = false {
        didSet { updateActivity() }
    }
    /// Растёт на каждой подаче. По нему мяч в трее улетает с ракетки
    @Published private(set) var serveCount = 0

    /// Минуты на линейке для обычного таймера
    @Published var selectedMinutes: Int {
        didSet { UserDefaults.standard.set(selectedMinutes, forKey: Self.minutesKey) }
    }
    /// Секунды на линейке, когда таймер выставляют в секундах
    @Published var selectedSeconds: Int {
        didSet { UserDefaults.standard.set(selectedSeconds, forKey: Self.secondsKey) }
    }
    /// В чём сейчас выставляется таймер. По умолчанию минуты
    @Published var unit: RulerUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: Self.unitKey) }
    }

    let pomodoro = PomodoroSettings()
    var onEvent: ((Event) -> Void)?

    /// Когда закончится текущая фаза. nil, пока таймер стоит или на паузе
    private(set) var endDate: Date?
    private var ticker: Timer?
    private var serveTask: Task<Void, Never>?
    private static let minutesKey = "timer.minutes"
    private static let secondsKey = "timer.seconds"
    private static let unitKey = "timer.unit"
    /// Сколько трей показывает подачу: мяч в ServeIcon улетает вдаль за 0.28 с,
    /// и сразу за этим квадрат растягивается в капсулу
    private static let serveDuration: Duration = .milliseconds(300)

    init() {
        let defaults = UserDefaults.standard
        let minutes = defaults.integer(forKey: Self.minutesKey)
        let seconds = defaults.integer(forKey: Self.secondsKey)
        selectedMinutes = Self.rulerRange.contains(minutes) ? minutes : 25
        selectedSeconds = Self.rulerRange.contains(seconds) ? seconds : 30
        unit = RulerUnit(rawValue: defaults.string(forKey: Self.unitKey) ?? "") ?? .minutes
    }

    var isActive: Bool { state != .idle }

    /// В чём сейчас линейка. Последнюю минуту любого таймера она идёт по секундам,
    /// идущее помодоро в остальное время — в минутах, а до старта и после конца — как выбрано.
    /// Сам выбор (unit) при этом не меняется, поэтому после конца линейка сама вернётся
    var rulerUnit: RulerUnit {
        guard isActive else { return unit }
        if remaining < 60 { return .seconds }
        return mode == .pomodoro ? .minutes : unit
    }

    /// Выбранное значение обычного таймера, в делениях линейки
    var selectedValue: Int {
        unit == .minutes ? selectedMinutes : selectedSeconds
    }

    /// Значение под указателем линейки: выбранное или остаток идущего таймера
    var rulerValue: Double {
        isActive ? Double(remaining) / Double(rulerUnit.step) : Double(selectedValue)
    }

    // MARK: - Управление

    func startTimer() {
        serve(.timer)
    }

    func startPomodoro() {
        serve(.pomodoro)
    }

    /// Подача: ракетка в трее бьёт по мячу со звуком, и время идёт сразу, с этого удара.
    /// Капсула раскрывается чуть позже, когда мяч улетел. Остаток округляется вверх,
    /// поэтому в первую секунду она всё равно показывает полное время, например 25:00
    private func serve(_ mode: Mode) {
        cancel()
        serveCount += 1
        // Подача поднимается раньше старта, чтобы трей ни на кадр не начал раскрываться
        isServing = true
        onEvent?(.serve)

        // Время идёт сразу, с удара
        self.mode = mode
        phase = .work
        cycle = 1
        let seconds = mode == .timer ? selectedValue * unit.step : pomodoro.workMinutes * 60
        begin(seconds: seconds)

        serveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.serveDuration)
            guard !Task.isCancelled else { return }
            self?.endServe()
        }
    }

    private func endServe() {
        isServing = false
        serveTask = nil
    }

    func pause() {
        guard state == .running, let end = endDate else { return }
        stopTicking()
        remaining = max(1, Int(end.timeIntervalSinceNow.rounded(.up)))
        endDate = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        begin(seconds: remaining)
    }

    func cancel() {
        serveTask?.cancel()
        serveTask = nil
        isServing = false
        stopTicking()
        endDate = nil
        remaining = 0
        state = .idle
        mode = .timer
        phase = .work
        cycle = 1
    }

    /// Значение с линейки: до старта это длина таймера, во время работы — новый остаток фазы
    func setRulerValue(_ value: Int) {
        let value = value.clamped(to: Self.rulerRange)
        switch state {
        case .idle:
            if unit == .minutes { selectedMinutes = value } else { selectedSeconds = value }
        case .running:
            begin(seconds: value * rulerUnit.step)
        case .paused:
            remaining = value * rulerUnit.step
        }
    }

    /// Пересчитать остаток прямо сейчас. Нужно после сна Mac
    func refresh() {
        if state == .running { scheduleTick() }
    }

    // MARK: - Ход времени

    private func begin(seconds: Int) {
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        remaining = seconds
        state = .running
        scheduleTick()
    }

    /// Обновляет остаток и ставит следующий тик ровно на момент, когда сменится целая секунда.
    /// Таймер в режиме .common, чтобы время шло и пока открыто меню или тянется линейка
    private func scheduleTick() {
        ticker?.invalidate()
        guard state == .running, let end = endDate else { return }

        let left = end.timeIntervalSinceNow
        if left <= 0 {
            remaining = 0
            phaseFinished()
            return
        }

        let seconds = Int(left.rounded(.up))
        if seconds != remaining { remaining = seconds }

        // Будим сразу после ближайшей смены целой секунды. В последнюю секунду
        // это и есть момент окончания, поэтому звук звучит ровно в ноль.
        // Раньше при остатке меньше 5 мс здесь ждали лишнюю целую секунду
        let wait = left - left.rounded(.down) + 0.005
        let timer = Timer(timeInterval: wait, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleTick() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Пока время идёт, не даём macOS «усыплять» приложение (App Nap).
    /// Под App Nap таймеры будят приложение с опозданием, и конец фазы со звуком запаздывает.
    /// Сон самого Mac не запрещаем: после него остаток пересчитается по endDate
    private var activity: NSObjectProtocol?

    private func updateActivity() {
        let needed = state == .running || isServing
        if needed, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: .userInitiatedAllowingIdleSystemSleep,
                reason: "Pong timer is running"
            )
        } else if !needed, let current = activity {
            ProcessInfo.processInfo.endActivity(current)
            activity = nil
        }
    }

    /// Фаза дошла до нуля: решаем, что дальше. В помодоро после последней работы отдыха нет
    private func phaseFinished() {
        stopTicking()
        endDate = nil

        switch (mode, phase) {
        case (.timer, _):
            cancel()
            onEvent?(.timerFinished)

        case (.pomodoro, .work):
            let total = pomodoro.cycles
            if cycle >= total {
                cancel()
                onEvent?(.pomodoroFinished(cycles: total))
            } else {
                phase = .rest
                begin(seconds: pomodoro.restMinutes * 60)
                onEvent?(.workFinished(cycle: cycle, of: total, restMinutes: pomodoro.restMinutes))
            }

        case (.pomodoro, .rest):
            cycle += 1
            phase = .work
            begin(seconds: pomodoro.workMinutes * 60)
            onEvent?(.restFinished(nextCycle: cycle, of: pomodoro.cycles, workMinutes: pomodoro.workMinutes))
        }
    }
}

/// Три настройки помодоро. Хранятся в UserDefaults и переживают перезапуск.
/// Меняются на лету: новая длина действует со следующей фазы
@MainActor
final class PomodoroSettings: ObservableObject {
    static let cyclesRange = 1...12
    static let workRange = 1...120
    static let restRange = 1...60

    @Published var cycles: Int { didSet { save(cycles, Keys.cycles) } }
    @Published var workMinutes: Int { didSet { save(workMinutes, Keys.work) } }
    @Published var restMinutes: Int { didSet { save(restMinutes, Keys.rest) } }

    private enum Keys {
        static let cycles = "pomodoro.cycles"
        static let work = "pomodoro.work"
        static let rest = "pomodoro.rest"
    }

    init() {
        cycles = Self.load(Keys.cycles, default: 4, range: Self.cyclesRange)
        workMinutes = Self.load(Keys.work, default: 25, range: Self.workRange)
        restMinutes = Self.load(Keys.rest, default: 5, range: Self.restRange)
    }

    /// Весь подход целиком: работа × циклы и отдых между ними
    var totalMinutes: Int {
        cycles * workMinutes + (cycles - 1) * restMinutes
    }

    private func save(_ value: Int, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func load(_ key: String, default value: Int, range: ClosedRange<Int>) -> Int {
        let saved = UserDefaults.standard.integer(forKey: key)
        return range.contains(saved) ? saved : value
    }
}

/// Как показывать время и длительности
enum TimeFormat {
    /// 25:00, 9:59, 1:05:00
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let h = s / 3600, m = s % 3600 / 60, sec = s % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, sec)
            : String(format: "%d:%02d", m, sec)
    }

    /// «1 h 55 min», «40 min»
    static func duration(minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
