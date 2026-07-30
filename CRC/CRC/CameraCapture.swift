//
//  CameraCapture.swift
//  CRC
//

import AVFoundation
import Combine

/// Dono da AVCaptureSession. Entrega cada CVPixelBuffer direto pro Vision
/// (sem conversão RGB — o Vision lê o buffer nativo).
final class CameraCapture: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

    let session = AVCaptureSession()

    /// Chamado na fila de vídeo (NÃO na main) com o buffer da câmera.
    var onPixelBuffer: ((CVPixelBuffer) -> Void)?

    private let queue = DispatchQueue(label: "camera.capture")

    func start() {
        queue.async { [weak self] in self?.configureAndRun() }
    }

    func stop() {
        queue.async { [weak self] in self?.session.stopRunning() }
    }

    private func configureAndRun() {
        session.beginConfiguration()

        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        print("[CAMERA] dispositivos:", discovery.devices.map { $0.localizedName })

        // Continuity Camera (iPhone) tem prioridade: imagem muito melhor que a builtin.
        // O iPhone chega como .external — o marcador confiável é isContinuityCamera.
        let preferred = discovery.devices.first { $0.isContinuityCamera }
        guard let device = preferred ?? discovery.devices.first ?? AVCaptureDevice.default(for: .video) else {
            print("[CAMERA] nenhum dispositivo de vídeo encontrado")
            session.commitConfiguration()
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                print("[CAMERA] não pôde adicionar a entrada")
                session.commitConfiguration()
                return
            }
            session.addInput(input)
            // Maior resolução que o dispositivo aceitar (16:9 — overlay conta com isso).
            for preset: AVCaptureSession.Preset in [.hd4K3840x2160, .hd1920x1080, .hd1280x720]
            where session.canSetSessionPreset(preset) {
                session.sessionPreset = preset
                break
            }
            print("[CAMERA] preset:", session.sessionPreset.rawValue)
        } catch {
            print("[CAMERA] erro na entrada:", error.localizedDescription)
            session.commitConfiguration()
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.alwaysDiscardsLateVideoFrames = true  // backpressure: descarta frame se o Vision está ocupado
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            print("[CAMERA] não pôde adicionar output")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)

        session.commitConfiguration()
        session.startRunning()
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let cb = onPixelBuffer, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        cb(pixelBuffer)  // processa inline na fila da câmera
    }
}

extension CameraCapture {
    /// Pede autorização de câmera e só então liga a session.
    func requestAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            start()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted { self?.start() } else { print("[CAMERA] permissão negada") }
            }
        default:
            print("[CAMERA] permissão negada/restrita — libere em Ajustes > Privacidade > Câmera")
        }
    }
}
