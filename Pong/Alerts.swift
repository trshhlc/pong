//
//  Alerts.swift
//  Pong
//
//  Звук и системное уведомление в конце фазы.
//  «Пинг» — закончилась работа, «понг» — закончился отдых или весь таймер.
//  На подаче, в момент старта, — тихий мягкий щелчок: тот же «понг», но вполголоса,
//  почти незаметный, и без уведомления.
//

import AppKit
import UserNotifications

@MainActor
final class Alerts: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func handle(_ event: TimerModel.Event) {
        switch event {
        case .serve: break
            // Тихий удар ракетки по мячу. Чтобы убрать звук на старте совсем, удали эту строку
            // play(serveTap)

        case .timerFinished:
            play(pop)
            notify("Time's up", "Timer finished")

        case let .workFinished(cycle, total, rest):
            play(ping)
            notify("Break · \(TimeFormat.duration(minutes: rest))", "Cycle \(cycle) of \(total) done")

        case let .restFinished(next, total, work):
            play(pop)
            notify("Back to work", "Cycle \(next) of \(total) · \(TimeFormat.duration(minutes: work))")

        case let .pomodoroFinished(cycles):
            play(pop)
            notify("Pomodoro done", "\(cycles) \(cycles == 1 ? "cycle" : "cycles") complete")
        }
    }

    /// Системные звуки из /System/Library/Sounds: Ping и Pop как раз про пинг-понг.
    /// Загружены заранее, чтобы в конце фазы не читать файл с диска
    private let ping = NSSound(named: NSSound.Name("Ping"))
    private let pop = NSSound(named: NSSound.Name("Pop"))

    /// Удар на подаче: Pop отдельной копией и на 20% громкости.
    /// Копия нужна, чтобы тише стал только этот звук, а не Pop в конце таймера
    private let serveTap: NSSound? = {
        let sound = NSSound(named: NSSound.Name("Pop"))?.copy() as? NSSound
        sound?.volume = 0.2
        return sound
    }()

    private func play(_ sound: NSSound?) {
        // Если звук ещё играет с прошлого раза, начинаем заново, а не молчим
        sound?.stop()
        sound?.play()
    }

    private func notify(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Звук играем сами, поэтому у уведомления он не нужен
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request)
    }

    /// Показывать баннер, даже когда открыто окно Pong
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}
