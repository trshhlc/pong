//
//  StatusItemController.swift
//  Pong
//
//  Кнопка в трее: левый клик открывает окно таймера, правый — меню.
//
//  Ширину кнопки ведёт своя пружина по кадрам экрана (CADisplayLink).
//  NSStatusItem не умеет анимировать длину сам: если просто присвоить новую,
//  строка меню прыгнет. Поэтому каждый кадр двигаем длину на шаг пружины.
//

import AppKit
import SwiftUI
import Combine
import ServiceManagement

@MainActor
final class StatusItemController: NSObject {
    private let model: TimerModel
    private let popup: PopupController
    private let tray = TrayState()
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let loginItem = NSMenuItem(title: "Launch at Login", action: nil, keyEquivalent: "")

    private var width = SpringValue(Metrics.idleWidth)
    private var displayLink: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0
    private var cancellables = Set<AnyCancellable>()

    init(model: TimerModel, popup: PopupController) {
        self.model = model
        self.popup = popup
        statusItem = NSStatusBar.system.statusItem(withLength: Metrics.idleWidth)
        super.init()

        setUpButton()
        setUpMenu()

        // Повторный клик, который закрывает окно, перехватывает PopupController,
        // поэтому о нём он сообщает сам — иконка тоже должна «нажаться»
        popup.onAnchorPress = { [weak self] in self?.tray.clicks += 1 }

        // Ширина зависит от состояния и длины текста времени.
        // Пока идёт подача, трей остаётся квадратом, хотя время уже идёт
        model.$state
            .combineLatest(model.$remaining, model.$isServing)
            .sink { [weak self] state, remaining, serving in
                self?.updateWidth(active: state != .idle && !serving, remaining: remaining)
            }
            .store(in: &cancellables)
    }

    private func setUpButton() {
        guard let button = statusItem.button else { return }

        let host = PassthroughHostingView(rootView: StatusItemView(model: model, tray: tray))
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: Metrics.idleWidth, height: NSStatusBar.system.thickness)
        host.autoresizingMask = [.width, .height]
        button.addSubview(host)

        button.target = self
        button.action = #selector(handleClick(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseUp])
        button.setAccessibilityLabel("Pong")
    }

    private func setUpMenu() {
        loginItem.target = self
        loginItem.action = #selector(toggleLaunchAtLogin(_:))
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
    }

    // MARK: - Клики

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }
        let isRight = event.type == .rightMouseUp || event.modifierFlags.contains(.control)

        if isRight {
            popup.close()
            loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            tray.clicks += 1
            popup.toggle(from: sender)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            print("Автозапуск: \(error)")
        }
        // macOS может попросить подтвердить автозапуск в настройках
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: - Пружина ширины

    private func updateWidth(active: Bool, remaining: Int) {
        let target = active
            ? Metrics.capsuleWidth(for: TimeFormat.clock(remaining))
            : Metrics.idleWidth
        guard target != width.target else { return }
        width.target = target
        startDisplayLink()
    }

    private func startDisplayLink() {
        guard displayLink == nil, let button = statusItem.button else { return }
        let link = button.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        lastFrame = 0
        displayLink = link
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = link.timestamp
        // Первый кадр и кадры после долгой паузы считаем обычными, чтобы пружина не «выстрелила»
        let dt = lastFrame == 0 ? 1.0 / 60 : min(now - lastFrame, 1.0 / 30)
        lastFrame = now

        width.step(dt)
        if width.isSettled {
            width.settle()
            statusItem.length = width.target
            link.invalidate()
            displayLink = nil
        } else {
            // Целые точки: дробная ширина размывает текст в трее
            statusItem.length = width.value.rounded()
        }
    }
}

/// Затухающая пружина, та же физика, что у SwiftUI .spring(response:dampingFraction:)
struct SpringValue {
    var value: CGFloat
    var target: CGFloat
    private var velocity: CGFloat = 0
    private let stiffness: CGFloat
    private let damping: CGFloat

    init(_ value: CGFloat, response: Double = Motion.response, dampingFraction: Double = Motion.damping) {
        self.value = value
        self.target = value
        stiffness = pow(2 * .pi / response, 2)
        damping = 4 * .pi * dampingFraction / response
    }

    mutating func step(_ dt: CFTimeInterval) {
        let force = -stiffness * (value - target) - damping * velocity
        velocity += force * dt
        value += velocity * dt
    }

    var isSettled: Bool {
        abs(velocity) < 2 && abs(value - target) < 0.3
    }

    mutating func settle() {
        value = target
        velocity = 0
    }
}

/// Что знает о трее только интерфейс, а не таймер
@MainActor
final class TrayState: ObservableObject {
    /// Растёт на каждом левом клике по иконке. По нему иконка «нажимается», как лапка в paw
    @Published var clicks = 0
}

/// SwiftUI внутри кнопки трея, который пропускает клики к самой кнопке
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
