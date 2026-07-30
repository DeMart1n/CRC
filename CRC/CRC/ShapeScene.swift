//
//  ShapeScene.swift
//  CRC
//
//  Lente Liquid Glass (glassEffect oficial do macOS 26) manipulada por gestos,
//  refratando o feed da câmera atrás dela:
//   • 1 pinça  → agarra e move (movimento relativo da mão)
//   • 2 pinças → afastar/aproximar escala; girar uma mão em volta da outra rotaciona
//  Posição/escala/rotação são @Published; a view é SwiftUI puro.
//

import SwiftUI
import Combine

@MainActor
final class GlassInteraction: ObservableObject {
    @Published private(set) var status = ""
    /// Centro da lente, normalizado (0..1) no espaço espelhado da tela.
    @Published private(set) var position = CGPoint(x: 0.5, y: 0.45)
    @Published private(set) var scale: CGFloat = 1
    @Published private(set) var rotation: Angle = .zero

    // Histerese da pinça: fecha em < 0.22 (dedos realmente juntos), solta em > 0.38
    // (ou sumindo por 5 frames).
    private var grabbing = false
    private var releaseFrames = 0
    private var lastCount = 0
    private var lastMid: CGPoint?
    private var lastDist: CGFloat?
    private var lastAngle: CGFloat?

    init() { updateStatus() }

    /// Chamado na main a cada frame com as mãos já filtradas.
    func update(hands: [Hand], now: Double) {
        let threshold: CGFloat = grabbing ? 0.38 : 0.22
        // Pontos de pinça (meio entre polegar e indicador), x espelhado como o preview.
        var pinches: [CGPoint] = []
        for hand in hands {
            guard let r = Gesture.pinchRatio(for: hand), r < threshold else { continue }
            let mx = 1 - CGFloat(hand[4][0] + hand[8][0]) / 2
            let my = CGFloat(hand[4][1] + hand[8][1]) / 2
            pinches.append(CGPoint(x: mx, y: my))
        }
        pinches.sort { $0.x < $1.x }  // ordem estável quando o tracker troca a ordem das mãos

        if pinches.isEmpty {
            releaseFrames += 1
            if releaseFrames > 5 { grabbing = false }
        } else {
            releaseFrames = 0
            grabbing = true
        }
        if pinches.count != lastCount {  // trocou o modo: recomeça os deltas
            lastMid = nil
            lastDist = nil
            lastAngle = nil
            lastCount = pinches.count
        }

        if pinches.count >= 2 {
            let a = pinches[0], b = pinches[1]
            let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let dist = hypot(b.x - a.x, b.y - a.y)
            let angle = atan2(b.y - a.y, b.x - a.x)
            if let lm = lastMid { translate(by: CGPoint(x: mid.x - lm.x, y: mid.y - lm.y)) }
            if let ld = lastDist, ld > 1e-3 {
                scale = min(max(scale * (dist / ld), 0.4), 3.0)
            }
            if let la = lastAngle {
                let delta = atan2(sin(angle - la), cos(angle - la))  // menor arco
                rotation += .radians(delta)
            }
            lastMid = mid
            lastDist = dist
            lastAngle = angle
        } else if pinches.count == 1 {
            if let lm = lastMid { translate(by: CGPoint(x: pinches[0].x - lm.x, y: pinches[0].y - lm.y)) }
            lastMid = pinches[0]
        }
        updateStatus()
    }

    private func translate(by delta: CGPoint) {
        position.x = min(max(position.x + delta.x, 0), 1)
        position.y = min(max(position.y + delta.y, 0), 1)
    }

    private func updateStatus() {
        switch lastCount {
        case 0: status = "vidro — pinça pra agarrar"
        case 1: status = "vidro — movendo"
        default: status = "vidro — escala + rotação"
        }
    }
}

/// Quadrado Liquid Glass por cima do preview da câmera.
struct GlassLens: View {
    @ObservedObject var lens: GlassInteraction

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .frame(width: 260, height: 260)
                // .clear: a variante mais transparente do Liquid Glass, refração mais visível.
                .glassEffect(.clear, in: .rect(cornerRadius: 56))
                .scaleEffect(lens.scale)
                .rotationEffect(lens.rotation)
                .position(x: lens.position.x * geo.size.width,
                          y: lens.position.y * geo.size.height)
        }
        .allowsHitTesting(false)
    }
}
