//
//  MenuBarIconContainer.swift
//  Pong
//

import AppKit

/// Контейнер для SwiftUI-иконки в строке меню.
///
/// Строка меню рисуется в vibrant-оформлении: системные иконки — шаблонные картинки, и цвет им
/// подбирает сама строка. В этом оформлении `.primary` специально бледнее, потому что рассчитан
/// на эту обработку, а наш SwiftUI-вид её не получает и выходит серым. Поэтому контейнер следит
/// за оформлением строки и даёт иконке обычное (aqua или darkAqua) той же яркости — тогда
/// `.primary` совпадает по цвету с остальными иконками.
final class MenuBarIconContainer: NSView {
    private let content: NSView

    init(content: NSView) {
        self.content = content
        super.init(frame: content.frame)
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) не используется") }

    // Клики проходят насквозь к кнопке строки меню, она сама открывает меню и переключает VPN
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        matchMenuBar()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        matchMenuBar()
    }

    private func matchMenuBar() {
        let match = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        let dark = match == .darkAqua || match == .vibrantDark
        content.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}
