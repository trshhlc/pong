//
//  ServeIcon.swift
//  Pong
//
//  Иконка в трее, пока таймер стоит: ракетка вырезана насквозь из квадрата цвета
//  строки меню, сверху лежит красный мяч. Расположение как на иконке приложения:
//  лопасть справа вверху, ручка уходит влево вниз, мяч слева вверху на краю лопасти.
//
//  Подача (TimerModel.serve). Ракетка бьёт по мячу, в этот момент звучит удар
//  (Alerts, событие .serve) и сразу пошло время. Мяч за 0.28 с улетает вдаль: через весь
//  квадрат к левому верхнему углу и чуть за него, уменьшаясь вдвое, но не исчезая.
//  Как только долетел (0.3 с, TimerModel.serveDuration), квадрат растягивается в капсулу.
//

import SwiftUI

struct ServeIcon: View {
    /// Каждое увеличение запускает подачу
    var serve: Int

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            KeyframeAnimator(initialValue: ServeFrame(), trigger: serve) { frame in
                ZStack(alignment: .topLeading) {
                    PaddleCutout(side: side)
                        .rotationEffect(.degrees(frame.tilt), anchor: ServeGeometry.pivot)
                        // Ракетка вырезает дыру в квадрате под ней, сквозь неё видна строка меню
                        .compositingGroup()
                        .blendMode(.destinationOut)
                    ball(side: side, flight: frame.flight)
                }
                .frame(width: side, height: side, alignment: .topLeading)
            } keyframes: { _ in
                // Мяч улетает вдаль за 0.28 с: сразу после удара быстрее, потом медленнее,
                // как настоящий в перспективе. На 0.3 с (TimerModel.serveDuration) иконка
                // сменилась капсулой. Если подачу отменили, мяч вернётся на ракетку
                KeyframeTrack(\.flight) {
                    LinearKeyframe(1, duration: 0.28, timingCurve: .away)
                    LinearKeyframe(1, duration: 0.25)
                    SpringKeyframe(0, duration: 0.3, spring: .snappy)
                }
                // Удар: ракетка резко идёт навстречу мячу и пружинит обратно
                KeyframeTrack(\.tilt) {
                    LinearKeyframe(-6, duration: 0.04)
                    SpringKeyframe(0, duration: 0.25, spring: .snappy)
                }
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    /// Мяч на пути вдаль: flight = 0 — лежит на ракетке, 1 — долетел до дальней точки.
    /// Чем дальше, тем меньше, но не меньше ServeGeometry.farScale
    private func ball(side: CGFloat, flight: CGFloat) -> some View {
        let g = ServeGeometry.self
        let center = CGPoint(
            x: g.contact.x + (g.far.x - g.contact.x) * flight,
            y: g.contact.y + (g.far.y - g.contact.y) * flight
        )
        let scale = 1 - (1 - g.farScale) * flight
        return Circle()
            .fill(Theme.accent)
            .frame(width: g.ballRadius * 2 * side, height: g.ballRadius * 2 * side)
            .scaleEffect(scale)
            .offset(x: (center.x - g.ballRadius) * side, y: (center.y - g.ballRadius) * side)
    }
}

/// Что меняется во время подачи
private struct ServeFrame {
    /// Сколько пути вдаль пролетел мяч: 0 — на ракетке, 1 — в дальней точке
    var flight: CGFloat = 0
    /// Наклон ракетки в градусах вокруг низа ручки
    var tilt: Double = 0
}

/// Ракетка в квадрате со стороной side: овальная лопасть и короткая толстая ручка.
/// Тонкая ручка с круглой лопастью читалась как лупа, поэтому пропорции как у настоящей ракетки
private struct PaddleCutout: View {
    let side: CGFloat

    var body: some View {
        let g = ServeGeometry.self
        ZStack(alignment: .topLeading) {
            Ellipse()
                .frame(width: g.headWidth * side, height: g.headLength * side)
                .rotationEffect(.degrees(g.handleAngle))
                .offset(x: (g.head.x - g.headWidth / 2) * side, y: (g.head.y - g.headLength / 2) * side)
            RoundedRectangle(cornerRadius: g.handleCorner * side, style: .continuous)
                .frame(width: g.handleWidth * side, height: g.handleLength * side)
                .rotationEffect(.degrees(g.handleAngle))
                .offset(
                    x: (g.handleCenter.x - g.handleWidth / 2) * side,
                    y: (g.handleCenter.y - g.handleLength / 2) * side
                )
        }
        .frame(width: side, height: side, alignment: .topLeading)
    }
}

/// Геометрия иконки в долях стороны квадрата: 0 — левый верхний угол, 1 — правый нижний
private enum ServeGeometry {
    /// Центр лопасти. Лопасть — овал, вытянутый вдоль ручки
    static let head = CGPoint(x: 0.59, y: 0.41)
    static let headLength: CGFloat = 0.64
    static let headWidth: CGFloat = 0.56
    /// Ручка: начинается внутри лопасти и уходит к левому нижнему углу
    static let handleFrom = CGPoint(x: 0.468, y: 0.542)
    static let handleTo = CGPoint(x: 0.197, y: 0.836)
    static let handleWidth: CGFloat = 0.19
    static let handleCorner: CGFloat = 0.05
    static let ballRadius: CGFloat = 0.13

    /// Центр мяча, когда он лежит на краю лопасти, как на иконке приложения
    static let contact = CGPoint(x: 0.2934, y: 0.3027)
    /// Дальняя точка полёта: за левым верхним углом квадрата. Путь — почти полквадрата.
    /// Дальше нельзя: у кнопки трея за квадратом всего 2 точки запаса, мяч бы обрезало
    static let far = CGPoint(x: -0.03, y: -0.04)
    /// Каким маленьким мяч становится вдали: 45% от размера на ракетке
    static let farScale: CGFloat = 0.45
    /// Вокруг чего ракетка поддаётся от удара — низ ручки
    static let pivot = UnitPoint(x: 0.197, y: 0.836)

    static var handleCenter: CGPoint {
        CGPoint(x: (handleFrom.x + handleTo.x) / 2, y: (handleFrom.y + handleTo.y) / 2)
    }

    static var handleLength: CGFloat {
        hypot(handleTo.x - handleFrom.x, handleTo.y - handleFrom.y)
    }

    /// Поворот вертикальных овала и ручки вдоль оси ракетки
    static var handleAngle: Double {
        atan2(-(handleTo.x - handleFrom.x), handleTo.y - handleFrom.y) * 180 / .pi
    }
}

private extension UnitCurve {
    /// Удаление в перспективу: сразу после удара мяч уходит быстрее, дальше медленнее.
    /// Квадратичное замедление: резче — и полёт пролетает незаметно
    static var away: UnitCurve {
        .bezier(startControlPoint: UnitPoint(x: 1 / 3, y: 2 / 3), endControlPoint: UnitPoint(x: 2 / 3, y: 1))
    }
}
