//
//  HandTracker.swift
//  CRC
//
//  Rastreamento de mãos nativo via Vision (VNDetectHumanHandPoseRequest).
//  Roda on-device acelerado por Neural Engine/GPU — sem Python, sem pipe.
//  Processa o CVPixelBuffer direto na fila da câmera; frames tardios são
//  descartados pelo alwaysDiscardsLateVideoFrames. Só o estado final volta pra main.
//

import Vision
import Combine
import QuartzCore

/// hands[m][p] = [x, y, confiança] normalizado (0..1). 21 pontos por mão.
typealias Hand = [[Float]]

final class HandTracker: ObservableObject {
    @Published private(set) var hands: [Hand] = []
    /// "E"/"D" por mão (mesma ordem de `hands`); "?" se o Vision não souber.
    @Published private(set) var chirality: [String] = []
    @Published private(set) var running = false
    @Published private(set) var recordingActive = false

    // Gravação de métricas (acessada na fila da câmera E na main → lock).
    private var recorder: MetricsRecorder?
    private let recorderLock = NSLock()

    func startMetricsRecording() {
        recorderLock.lock()
        recorder = MetricsRecorder()
        recorderLock.unlock()
        DispatchQueue.main.async { self.recordingActive = true }
    }

    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    private let filter = HandFilter()
    private var lastTime = 0.0

    // ponytail: stride=1 (30fps) prioriza precisão; suba pra 2 se CPU/bateria pesar.
    private let frameStride = 1
    private var frameIndex = 0

    /// Ordem dos 21 pontos igual à do MediaPipe (0 = pulso, 1–4 polegar, …),
    /// pra reaproveitar overlay e gestos sem mudar índice.
    private static let joints: [VNHumanHandPoseObservation.JointName] = [
        .wrist,
        .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
        .indexMCP, .indexPIP, .indexDIP, .indexTip,
        .middleMCP, .middlePIP, .middleDIP, .middleTip,
        .ringMCP, .ringPIP, .ringDIP, .ringTip,
        .littleMCP, .littlePIP, .littleDIP, .littleTip,
    ]

    func start() { DispatchQueue.main.async { self.running = true } }
    func stop() { DispatchQueue.main.async { self.running = false } }

    /// Chamado na fila da câmera (off main).
    func process(_ pixelBuffer: CVPixelBuffer) {
        frameIndex += 1
        guard frameIndex % frameStride == 0 else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            print("[VISION] erro: \(error.localizedDescription)")
            return
        }

        var out: [Hand] = []
        var sides: [String] = []
        for obs in request.results ?? [] {
            guard let points = try? obs.recognizedPoints(.all) else { continue }
            var hand = Hand()
            hand.reserveCapacity(21)
            for j in Self.joints {
                if let p = points[j], p.confidence > 0.5 {
                    // Vision: origem inferior-esquerda → inverte y pra topo-esquerda.
                    // Terceiro valor guarda a confiança (no lugar do z que o Vision não dá).
                    hand.append([Float(p.location.x), Float(1 - p.location.y), p.confidence])
                } else {
                    hand.append([0, 0, 0])  // ponto ausente
                }
            }
            // Mão saindo do quadro: sobram poucos pontos confiáveis e eles pulam
            // (teleporte). Melhor não inferir nada do que inferir errado.
            guard hand.filter({ $0[2] > 0 }).count >= 12 else { continue }
            switch obs.chirality {
            case .left: sides.append("E")
            case .right: sides.append("D")
            default: sides.append("?")
            }
            out.append(hand)
        }

        let now = CACurrentMediaTime()
        let dt = lastTime == 0 ? 1.0 / 30 : now - lastTime
        lastTime = now
        let filtered = filter.apply(out, dt: dt)

        recorderLock.lock()
        if let rec = recorder,
           !rec.record(t: now, raw: out, filtered: filtered,
                       width: CVPixelBufferGetWidth(pixelBuffer),
                       height: CVPixelBufferGetHeight(pixelBuffer)) {
            recorder = nil
            DispatchQueue.main.async { self.recordingActive = false }
        }
        recorderLock.unlock()

        DispatchQueue.main.async {
            self.hands = filtered
            self.chirality = sides
        }
    }
}
