//
//  PongApp.swift
//  Pong
//
//  Таймер и помодоро в трее macOS. Окна в Dock нет (LSUIElement),
//  всё живёт в кнопке строки меню и окне под ней.
//

import SwiftUI

@main
struct PongApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: TimerModel?
    private var alerts: Alerts?
    private var popup: PopupController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = TimerModel()
        let alerts = Alerts()
        let popup = PopupController(model: model)
        statusItem = StatusItemController(model: model, popup: popup)

        model.onEvent = { [weak alerts] event in alerts?.handle(event) }
        alerts.requestPermission()

        // После сна Mac сразу пересчитываем остаток, не дожидаясь следующего тика
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak model] _ in
            MainActor.assumeIsolated { model?.refresh() }
        }

        self.model = model
        self.alerts = alerts
        self.popup = popup
    }
}
