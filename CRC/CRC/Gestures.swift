//
//  Gestures.swift
//  CRC
//
//  Reconhecimento simples de gestos a partir dos 21 landmarks (2D x,y).
//  Tudo por heurística geométrica normalizada pelo tamanho da mão — sem tocar no Python.
//

import Foundation
import CoreGraphics

enum Gesture {
    /// Nome do gesto para uma mão (21 pontos). "" se inválida.
    static func name(for hand: Hand) -> String {
        guard hand.count == 21 else { return "" }

        func d(_ a: Int, _ b: Int) -> CGFloat {
            hypot(CGFloat(hand[a][0] - hand[b][0]), CGFloat(hand[a][1] - hand[b][1]))
        }

        let scale = max(d(0, 9), 1e-4)  // pulso → base do dedo médio, referência de tamanho

        // Dedo estendido: ponta mais longe do pulso que a junta PIP.
        let tips = [8, 12, 16, 20], pips = [6, 10, 14, 18]
        let fingers = zip(tips, pips).map { d($0.0, 0) > d($0.1, 0) }  // [indicador, médio, anelar, mindinho]

        // ponytail: polegar por heurística (ponta afastada do pulso e da base do indicador);
        // calibrar os fatores 0.5 se falhar em mãos muito abertas/fechadas.
        let thumb = d(4, 0) > d(3, 0) && d(4, 5) > 0.5 * scale

        let count = fingers.filter { $0 }.count + (thumb ? 1 : 0)
        let pinch = d(4, 8) < 0.35 * scale  // ponta polegar ↔ ponta indicador

        if pinch { return "pinça" }
        if fingers[0] && !fingers[1] && !fingers[2] && !fingers[3] { return "apontar" }
        if count == 0 { return "punho" }
        if count >= 4 { return "mão aberta" }
        return "\(count) dedos"
    }

    /// Distância polegar↔indicador normalizada pelo tamanho da mão; nil se não é
    /// uma pinça deliberada (pontos ausentes, ou mão fechando — médio colado no
    /// polegar significa punho, não pinça).
    static func pinchRatio(for hand: Hand) -> CGFloat? {
        guard hand.count == 21, hand[4][2] > 0, hand[8][2] > 0 else { return nil }
        func d(_ a: Int, _ b: Int) -> CGFloat {
            hypot(CGFloat(hand[a][0] - hand[b][0]), CGFloat(hand[a][1] - hand[b][1]))
        }
        let scale = max(d(0, 9), 1e-4)
        if hand[12][2] > 0 && d(4, 12) / scale < 0.35 { return nil }
        return d(4, 8) / scale
    }
}
