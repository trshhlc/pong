//
//  StatusItemView.swift
//  Pong
//
//  Что нарисовано в трее. Фон один и тот же всё время: пока таймер стоит, это квадрат
//  с вырезанной ракеткой и красным мячом (ServeIcon), пока идёт — тот же квадрат,
//  растянутый в капсулу со временем.
//
//  Фон монохромный, как системные иконки: цвета строки меню, а ракетка и время в нём
//  вырезаны насквозь. На отдыхе капсула становится красной, на паузе — контуром.
//
//  Старт начинается с подачи: удар со звуком, время сразу пошло, а мяч за 0.3 с
//  улетает с ракетки (TimerModel.serve). Потом плавность складывается из трёх слоёв:
//  1. ширину кнопки раздвигает пружина в StatusItemController, квадрат тянется в капсулу;
//  2. ракетка с мячом гаснут;
//  3. время въезжает снизу с увеличением чуть позже, когда капсула уже раскрылась.
//  Если запустить всё одновременно, выглядит дёшево — задержка и делает «дорого».
//

import SwiftUI

/// Вид фона: таймер стоит, идёт работа или обычный таймер, идёт отдых, пауза
enum TrayLook {
    case idle, work, rest, paused
}

struct StatusItemView: View {
    @ObservedObject var model: TimerModel
    @ObservedObject var tray: TrayState

    /// Капсула со временем. Пока мяч улетает на подаче, ещё ракетка, хотя время уже идёт
    private var showsTime: Bool {
        model.isActive && !model.isServing
    }

    private var look: TrayLook {
        guard showsTime else { return .idle }
        switch model.state {
        case .idle: return .idle
        case .paused: return .paused
        case .running: return model.mode == .pomodoro && model.phase == .rest ? .rest : .work
        }
    }

    private var textColor: Color {
        switch look {
        case .idle, .work: .primary // цвет не важен: текст вырезается из капсулы
        case .rest: Theme.ink
        case .paused: .primary.opacity(0.65)
        }
    }

    var body: some View {
        ZStack {
            // Один фон на всё время: квадрат в покое, капсула во время работы
            TrayCapsule(look: look)
                .padding(.horizontal, Metrics.capsuleInset)
                .padding(.vertical, Metrics.capsuleVInset)

            if showsTime {
                Text(TimeFormat.clock(model.remaining))
                    .font(Font(Metrics.trayFont))
                    .foregroundStyle(textColor)
                    // На работе время вырезано из капсулы и сквозь него видна строка меню
                    .blendMode(look == .work ? .destinationOut : .normal)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .fixedSize()
                    .transition(.asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.7))
                            .combined(with: .offset(y: 4))
                            .animation(Motion.spring.delay(0.1)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))
                    ))
            } else {
                // На каждой подаче мяч улетает с ракетки, и трей раскрывается в капсулу
                ServeIcon(serve: model.serveCount)
                    .padding(.horizontal, Metrics.capsuleInset)
                    .padding(.vertical, Metrics.capsuleVInset)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.4)
                            .combined(with: .opacity)
                            .animation(Motion.spring.delay(0.12)),
                        removal: .scale(scale: 0.4)
                            .combined(with: .opacity)
                            .animation(.easeIn(duration: 0.12))
                    ))
            }
        }
        // Вырез ракетки и текста действует только внутри этой группы, а не на всю строку меню
        .compositingGroup()
        // Нажатие, как у лапки в paw (.bounce.down): иконка вжимается и пружинит обратно.
        // Иконка нарисована фигурами, а не SF Symbol, поэтому эффект повторён ключевыми кадрами
        .keyframeAnimator(initialValue: CGFloat(1), trigger: tray.clicks) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.8, duration: 0.09)
                SpringKeyframe(1, duration: 0.4, spring: .bouncy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(Motion.spring, value: showsTime)
        .animation(Motion.snappy, value: model.remaining)
        .animation(.easeInOut(duration: 0.25), value: look)
    }
}

/// Фон: квадрат в покое и капсула во время работы. Заливка и обводка лежат друг на друге
/// и плавно меняются местами, поэтому переход «работа → пауза → отдых» тоже анимируется
struct TrayCapsule: View {
    let look: TrayLook

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.trayCorner, style: .continuous)
        ZStack {
            shape
                .fill(look == .rest ? Theme.accent : Color.primary)
                .opacity(look == .paused ? 0 : 1)
            shape
                .strokeBorder(Color.primary.opacity(0.5), lineWidth: 1.2)
                .opacity(look == .paused ? 1 : 0)
        }
    }
}
