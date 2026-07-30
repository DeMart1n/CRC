//
//  HandOverlay.swift
//  CRC
//
//  Desenha os 21 keypoints e as conexões (ossos) que o MediaPipe devolve,
//  por cima do preview. Coordenadas normalizadas (0..1) mapeadas no retângulo
//  4:3 ajustado (mesma proporção que é enviada ao Python).
//

import SwiftUI

/// Conexões oficiais do HandLandmarker (21 pontos): dedos + palma.
private let handConnections: [(Int, Int)] = [
    (0, 1), (1, 2), (2, 3), (3, 4),        // polegar
    (0, 5), (5, 6), (6, 7), (7, 8),        // indicador
    (5, 9), (9, 10), (10, 11), (11, 12),   // médio
    (9, 13), (13, 14), (14, 15), (15, 16), // anelar
    (13, 17), (17, 18), (18, 19), (19, 20),// mindinho
    (0, 17),                               // base da palma
]

// Mesma proporção do sessionPreset da câmera (720p 16:9).
private let contentAspect = 1280.0 / 720.0

struct HandOverlay: View {
    let hands: [Hand]

    var body: some View {
        Canvas { ctx, size in
            let r = fittedRect(in: size)
            for hand in hands where hand.count == 21 {
                // x espelhado pra casar com o preview em modo selfie (isVideoMirrored).
                let pts = hand.map { lm in
                    CGPoint(x: r.minX + (1 - CGFloat(lm[0])) * r.width,
                            y: r.minY + CGFloat(lm[1]) * r.height)
                }
                let conf = hand.map { $0[2] }  // confiança por ponto (0 = ausente)

                // ossos: pula conexão se algum extremo está ausente
                var bones = Path()
                for (a, b) in handConnections where conf[a] > 0 && conf[b] > 0 {
                    bones.move(to: pts[a])
                    bones.addLine(to: pts[b])
                }
                ctx.stroke(bones, with: .color(.white.opacity(0.55)), lineWidth: 2)

                // juntas: opacidade pela confiança
                for (i, p) in pts.enumerated() where conf[i] > 0 {
                    let radius: CGFloat = 5
                    let dot = Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius,
                                                     width: radius * 2, height: radius * 2))
                    ctx.fill(dot, with: .color(Color(hue: 0.33, saturation: 0.9, brightness: 1,
                                                     opacity: 0.35 + 0.65 * Double(conf[i]))))
                }

                // nome do gesto acima do pulso
                let label = conf[0] > 0 ? Gesture.name(for: hand) : ""
                if !label.isEmpty {
                    let text = Text(label)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.yellow)
                    ctx.draw(text, at: CGPoint(x: pts[0].x, y: pts[0].y + 26), anchor: .center)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// Retângulo 4:3 que PREENCHE `size` recortando o excesso (mesma lógica do .resizeAspectFill).
    /// Pode extrapolar os limites da view; os pontos fora simplesmente saem da tela.
    private func fittedRect(in size: CGSize) -> CGRect {
        if size.width / size.height > contentAspect {
            // view mais larga que 4:3 → preenche pela largura, sobra em cima/baixo
            let h = size.width / contentAspect
            return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
        } else {
            let w = size.height * contentAspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
    }
}
