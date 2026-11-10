//
//  Theme.swift
//  Pong
//
//  Цвета, размеры и пружины. Красный, как мяч на иконке приложения, — единственный
//  акцент: мяч в трее, капсула на отдыхе, указатель линейки, пройденные циклы.
//  Остальное монохромное.
//

import SwiftUI
import AppKit

enum Theme {
    /// Красный мяч, #FF282D — снят с мяча на иконке приложения.
    /// Единственный цвет в ассетах, меняется в Xcode: Assets.xcassets → accent
    static let accent = Color("accent")
    /// Тёмный текст поверх красного
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
}

enum Metrics {
    /// Шрифт времени в трее: 13 pt, medium, моноширинные цифры.
    /// Один на всё: им рисуется текст в StatusItemView и по нему же считается ширина капсулы,
    /// поэтому размер или вес меняются только здесь
    static var trayFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium)
    }
    /// Отступ текста от края капсулы
    static let capsulePadding: CGFloat = 8
    /// Отступ капсулы от края кнопки в трее: по бокам и сверху-снизу
    static let capsuleInset: CGFloat = 2
    static let capsuleVInset: CGFloat = 2.5
    /// Сторона квадрата в покое — это высота капсулы: высота строки меню без отступов
    @MainActor static var trayIconSide: CGFloat {
        NSStatusBar.system.thickness - 2 * capsuleVInset
    }
    /// Ширина кнопки в трее, пока таймер стоит: ровно квадрат и отступы по бокам.
    /// При старте этот квадрат и растягивается в капсулу
    @MainActor static var idleWidth: CGFloat {
        trayIconSide + 2 * capsuleInset
    }
    /// Скругление капсулы в трее: чуть квадратнее полной капсулы
    static let trayCorner: CGFloat = 5.5

    static let popupSize = NSSize(width: 320, height: 216)
    static let popupCorner: CGFloat = 16
    static let popupPadding: CGFloat = 16

    /// Расстояние между минутами на линейке
    static let tickSpacing: CGFloat = 9
    static let rulerHeight: CGFloat = 44
    static var rulerWidth: CGFloat { popupSize.width - popupPadding * 2 }
    /// Поле слева от нулевой отметки, чтобы её не обрезало
    static let rulerLead: CGFloat = 24
    static var rulerStripWidth: CGFloat {
        rulerLead * 2 + CGFloat(TimerModel.rulerRange.upperBound) * tickSpacing
    }

    /// Ширина капсулы под текст времени. Цифры моноширинные,
    /// поэтому меряем шаблон из нулей: ширина меняется только когда меняется число знаков
    static func capsuleWidth(for text: String) -> CGFloat {
        let template = String(text.map { $0.isNumber ? "0" : $0 })
        let width = (template as NSString).size(withAttributes: [.font: trayFont]).width
        return ceil(width) + 2 * (capsulePadding + capsuleInset)
    }
}

/// Пружины. Ширину трея ведёт своя AppKit-пружина с теми же числами,
/// поэтому капсула и всё внутри неё двигаются в одном ритме
enum Motion {
    static let response = 0.42
    static let damping = 0.75
    static let spring = Animation.spring(response: response, dampingFraction: damping)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.86)
}

extension NSImage {
    /// Маска со скруглёнными углами для NSVisualEffectView: растягивается без искажения углов
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
