//
//  MetricsRecorder.swift
//  CRC
//
//  Gravação de métricas pro analyze_tracking.py: por frame, timestamp relativo,
//  dt real (pra fps medido), resolução do buffer, landmarks crus (pós-Vision,
//  pré-filtro — já com o corte de confiança 0.5 aplicado, pontos ausentes = [0,0,0])
//  e os mesmos landmarks depois do HandFilter. Para sozinho após `duration`
//  e salva JSON em Documents (caminho impresso no console como [REC]).
//

import Foundation

final class MetricsRecorder {
    private let duration: Double
    private var start = 0.0
    private var last = 0.0
    private var width = 0
    private var height = 0
    private var frames: [[String: Any]] = []

    init(duration: Double = 20) { self.duration = duration }

    /// Chamado na fila da câmera. Retorna false quando terminou (já salvou).
    func record(t: Double, raw: [Hand], filtered: [Hand], width: Int, height: Int) -> Bool {
        if start == 0 { start = t; print("[REC] gravando \(Int(duration))s…") }
        self.width = width
        self.height = height
        func dump(_ hands: [Hand]) -> [[[Double]]] {
            hands.map { $0.map { $0.map(Double.init) } }
        }
        frames.append([
            "t": t - start,
            "dt": last == 0 ? 0.0 : t - last,
            "raw": dump(raw),
            "filtered": dump(filtered),
        ])
        last = t
        if t - start >= duration { save(); return false }
        return true
    }

    private func save() {
        let doc: [String: Any] = ["width": width, "height": height, "frames": frames]
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent("crc-rec-\(fmt.string(from: Date())).json")
        do {
            let data = try JSONSerialization.data(withJSONObject: doc)
            try data.write(to: url)
            print("[REC] salvo: \(url.path) (\(frames.count) frames)")
        } catch {
            print("[REC] erro ao salvar: \(error)")
        }
    }
}
