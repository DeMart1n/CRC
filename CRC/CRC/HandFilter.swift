//
//  HandFilter.swift
//  CRC
//
//  One Euro Filter (Casiez et al., CHI 2012) ciente de confiança, aplicado a x,y
//  de cada landmark. A 3ª componente é a confiança (passa direto, não é filtrada).
//  Parado: suaviza forte (tira jitter). Em movimento: afrouxa (tira lag).
//  Pontos ausentes seguram a última posição; saltos absurdos num frame são rejeitados.
//

import Foundation

final class HandFilter {
    // Botões de calibração:
    // minCutoff menor = mais suave/estável parado. beta maior = responde mais rápido.
    // Valores escolhidos por sweep offline nos dados gravados (analyze_tracking.py --sweep):
    // 1.0/10.0 = jitter 0.73 px (era 0.94) e latência 23.5 ms (era 53.6) a 30 fps.
    // Em coordenadas normalizadas a velocidade da mão é ~1-2 u/s — beta < 1 quase não age.
    var minCutoff = 1.0
    var beta = 10.0
    private let dCutoff = 1.0

    // Salto (em coord normalizada) acima do qual a amostra é tratada como outlier.
    private let maxJump = 0.2
    // Dois outliers seguidos a menos que isso um do outro = movimento real, aceita.
    private let confirmRadius = 0.08

    private var xp: [[[Double]]] = []      // último valor cru (x,y)
    private var xHat: [[[Double]]] = []    // último valor filtrado (x,y)
    private var dxHat: [[[Double]]] = []   // última derivada filtrada (x,y)
    private var pending: [[[Double]?]] = []  // outlier aguardando confirmação

    /// Filtra `hands` dado o intervalo `dt` (s) desde o frame anterior.
    func apply(_ hands: [Hand], dt: Double) -> [Hand] {
        let te = max(dt, 1e-3)

        // Mudou o número de mãos/pontos: reinicia.
        guard sameShape(hands) else {
            xp = hands.map { $0.map { [Double($0[0]), Double($0[1])] } }
            xHat = xp
            dxHat = hands.map { $0.map { _ in [0, 0] } }
            pending = hands.map { $0.map { _ in nil } }
            return hands
        }

        var out = hands
        for h in hands.indices {
            for p in hands[h].indices {
                let conf = hands[h][p].count > 2 ? hands[h][p][2] : 1

                // Ausente: segura a última posição filtrada (não vai pro canto).
                if conf <= 0 {
                    out[h][p][0] = Float(xHat[h][p][0])
                    out[h][p][1] = Float(xHat[h][p][1])
                    continue
                }

                let rx = Double(hands[h][p][0]), ry = Double(hands[h][p][1])
                let jump = hypot(rx - xHat[h][p][0], ry - xHat[h][p][1])

                if jump > maxJump {
                    if let prev = pending[h][p], hypot(rx - prev[0], ry - prev[1]) < confirmRadius {
                        // Confirmado: dois frames apontam pro mesmo lugar → movimento real.
                        // Realinha o filtro no destino (sem interpolar pelo meio do caminho).
                        pending[h][p] = nil
                        xp[h][p] = [rx, ry]
                        xHat[h][p] = [rx, ry]
                        dxHat[h][p] = [0, 0]
                        out[h][p][0] = Float(rx)
                        out[h][p][1] = Float(ry)
                    } else {
                        // Suspeito: guarda e segura a posição anterior por enquanto.
                        pending[h][p] = [rx, ry]
                        out[h][p][0] = Float(xHat[h][p][0])
                        out[h][p][1] = Float(xHat[h][p][1])
                    }
                    continue
                }
                pending[h][p] = nil

                // One Euro em x e y.
                for c in 0..<2 {
                    let v = Double(hands[h][p][c])
                    let dx = (v - xp[h][p][c]) / te
                    let ad = alpha(dCutoff, te)
                    let dHat = ad * dx + (1 - ad) * dxHat[h][p][c]
                    let cutoff = minCutoff + beta * abs(dHat)
                    let a = alpha(cutoff, te)
                    let xh = a * v + (1 - a) * xHat[h][p][c]
                    xp[h][p][c] = v
                    dxHat[h][p][c] = dHat
                    xHat[h][p][c] = xh
                    out[h][p][c] = Float(xh)
                }
            }
        }
        return out
    }

    private func sameShape(_ hands: [Hand]) -> Bool {
        guard xHat.count == hands.count else { return false }
        for h in hands.indices where xHat[h].count != hands[h].count { return false }
        return true
    }

    private func alpha(_ cutoff: Double, _ dt: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
