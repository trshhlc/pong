//
//  PopupController.swift
//  Pong
//
//  Окно таймера под кнопкой в трее. Своя панель вместо NSPopover: без стрелки,
//  со своей анимацией появления и с клавишами.
//
//  Клавиши: пробел или Return — старт/пауза, ←/→ — минута туда-сюда, Esc — закрыть.
//  Свайп по трекпаду или колесо мыши крутят линейку.
//

import AppKit
import SwiftUI

@MainActor
final class PopupController: NSObject {
    let presence = PopupPresence()
    private let model: TimerModel
    private let ruler: RulerController
    private let panel: PopupPanel
    private weak var anchor: NSStatusBarButton?
    private var monitors: [Any] = []
    private(set) var isOpen = false
    /// Повторный левый клик по иконке, который закрыл окно. Кнопка трея его не получает
    var onAnchorPress: (@MainActor () -> Void)?

    init(model: TimerModel) {
        self.model = model
        ruler = RulerController(model: model)
        panel = PopupPanel(size: Metrics.popupSize)
        super.init()

        let actions = PopupActions(
            primary: { [weak self] in self?.primaryAction() },
            cancel: { [weak self] in self?.cancelAction() },
            openPomodoro: { [weak self] in self?.showPage(.pomodoro) },
            back: { [weak self] in self?.showPage(.timer) },
            startPomodoro: { [weak self] in self?.startPomodoro() }
        )
        let root = PopupView(model: model, presence: presence, ruler: ruler, actions: actions)

        // Размытый фон как у системных поповеров, углы скругляет маска.
        // Тень окна macOS строит по прозрачности, поэтому она тоже скруглённая
        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: Metrics.popupSize))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = .roundedMask(radius: Metrics.popupCorner)

        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.frame = background.bounds
        host.autoresizingMask = [.width, .height]
        background.addSubview(host)
        panel.contentView = background
    }

    // MARK: - Показ и скрытие

    func toggle(from button: NSStatusBarButton) {
        isOpen ? close() : show(from: button)
    }

    func show(from button: NSStatusBarButton) {
        guard !isOpen else { return }
        isOpen = true
        anchor = button
        presence.page = .timer

        // Окно выезжает на 6 точек сверху вниз и проявляется
        let frame = targetFrame(below: button)
        panel.setFrame(frame.offsetBy(dx: 0, dy: 6), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }

        button.highlight(true)
        installMonitors()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        removeMonitors()
        anchor?.highlight(false)

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Если за это время окно открыли снова, не прячем его
                guard let self, !self.isOpen else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    /// Под кнопкой по центру, но не за краем экрана
    private func targetFrame(below button: NSStatusBarButton) -> NSRect {
        let size = Metrics.popupSize
        guard let window = button.window else { return NSRect(origin: .zero, size: size) }

        let anchorRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        var x = anchorRect.midX - size.width / 2
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, visible.minX + 6), visible.maxX - size.width - 6)
        }
        let y = anchorRect.minY - 6 - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Действия

    private func primaryAction() {
        Haptics.tap()
        switch model.state {
        case .idle:
            model.startTimer()
            // Закрываем окно, чтобы было видно подачу мяча и как раскрывается капсула
            close()
        case .running:
            withAnimation(Motion.snappy) { model.pause() }
        case .paused:
            withAnimation(Motion.snappy) { model.resume() }
        }
    }

    private func cancelAction() {
        Haptics.tap()
        withAnimation(Motion.spring) { model.cancel() }
    }

    private func startPomodoro() {
        Haptics.tap()
        model.startPomodoro()
        close()
    }

    private func showPage(_ page: PopupPresence.Page) {
        withAnimation(Motion.spring) { presence.page = page }
    }

    // MARK: - События

    private func installMonitors() {
        removeMonitors()

        // Клик в другом приложении закрывает окно.
        // Клик по нашей иконке сюда не относится: его разбирает handleLocal
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isMouseOnAnchor() else { return }
                self.close()
            }
        }) {
            monitors.append(global)
        }

        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel], handler: { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handleLocal(event) ?? false }
            return consumed ? nil : event
        }) {
            monitors.append(local)
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// true — событие обработано и дальше не идёт
    private func handleLocal(_ event: NSEvent) -> Bool {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            if event.window === panel { return false }

            if isMouseOnAnchor() {
                // Повторный левый клик по иконке закрывает окно прямо здесь, а событие гасим.
                // Иначе до кнопки дойдёт тот же клик, и она откроет окно заново.
                // Правый клик и Ctrl+клик пропускаем: кнопка сама закроет окно и покажет меню
                let opensMenu = event.type == .rightMouseDown || event.modifierFlags.contains(.control)
                if opensMenu { return false }
                onAnchorPress?()
                close()
                return true
            }

            close()
            return false

        case .scrollWheel:
            guard event.window === panel, presence.page == .timer else { return false }
            ruler.scroll(event)
            return true

        case .keyDown:
            guard event.window === panel else { return false }
            return handleKey(event)

        default:
            return false
        }
    }

    /// Курсор над иконкой в трее. Смотрим по координатам экрана, а не по окну события:
    /// окно у кликов по строке меню бывает не тем, что у кнопки
    private func isMouseOnAnchor() -> Bool {
        guard let button = anchor, let window = button.window else { return false }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        // Запас по вертикали: самый верхний пиксель экрана тоже считается кликом по иконке
        return rect.insetBy(dx: 0, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let escape: UInt16 = 53, space: UInt16 = 49, enter: UInt16 = 36, keypadEnter: UInt16 = 76
        let left: UInt16 = 123, right: UInt16 = 124
        let key = event.keyCode

        switch presence.page {
        case .timer:
            switch key {
            case escape: close()
            case space, enter, keypadEnter: primaryAction()
            case left: ruler.step(by: -1)
            case right: ruler.step(by: 1)
            default: return false
            }
        case .pomodoro:
            switch key {
            case escape: showPage(.timer)
            case space, enter, keypadEnter: startPomodoro()
            default: return false
            }
        }
        return true
    }
}

/// Какая страница открыта в окне
@MainActor
final class PopupPresence: ObservableObject {
    enum Page { case timer, pomodoro }
    @Published var page: Page = .timer
}

/// Кнопки окна зовут контроллер через эти замыкания
struct PopupActions {
    var primary: @MainActor () -> Void
    var cancel: @MainActor () -> Void
    var openPomodoro: @MainActor () -> Void
    var back: @MainActor () -> Void
    var startPomodoro: @MainActor () -> Void
}

/// Панель без рамки, которая не активирует приложение, но принимает клавиши
final class PopupPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
