//
//  ContentView.swift
//  CRC
//
//  Janela de preview/debug. O pipeline roda no AppModel independente dela.
//

import SwiftUI
import AVFoundation

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var tracker: HandTracker
    @ObservedObject var lens: GlassInteraction

    init(model: AppModel) {
        self.model = model
        self.tracker = model.tracker
        self.lens = model.lens
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            CameraPreview(session: model.camera.session)
                .frame(minWidth: 320, minHeight: 320)  // min baixo pro formato vertical caber

            GlassLens(lens: lens)

            HandOverlay(hands: tracker.hands)

            VStack(alignment: .leading, spacing: 8) {
                Label("CRC — liquid glass por gestos", systemImage: "hand.raised.fill")
                    .font(.system(.title3, design: .rounded).bold())
                HStack(spacing: 6) {
                    Circle()
                        .fill(tracker.hands.isEmpty ? .red : .green)
                        .frame(width: 9, height: 9)
                    Text(tracker.hands.isEmpty ? "procurando mãos…" : "\(tracker.hands.count) mão(s)")
                }
                .font(.system(.callout, design: .monospaced))
                Text(lens.status)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.cyan)
                // Aqui além do menu bar: o macOS esconde o ícone quando a barra lota.
                Button(tracker.recordingActive ? "● gravando…" : "Gravar métricas (20s)") {
                    tracker.startMetricsRecording()
                }
                .disabled(tracker.recordingActive)
                .keyboardShortcut("r")
            }
            .padding(14)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))  // Liquid Glass oficial
            .foregroundStyle(.white)
            .padding()
            .padding(.top, 28)
        }
        .ignoresSafeArea()
    }
}

/// Preview nativo via AVCaptureVideoPreviewLayer.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        // Espelhado (selfie): o HandOverlay espelha o x junto, então continua alinhado.
        // O Vision segue analisando o buffer não-espelhado — só a exibição flipa.
        // connection é nil até a session ter input; reaplica quando ela começa a rodar.
        Self.applyMirror(preview)
        NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification,
            object: session, queue: .main
        ) { [weak preview] _ in
            if let preview { Self.applyMirror(preview) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private static func applyMirror(_ layer: AVCaptureVideoPreviewLayer) {
        guard let conn = layer.connection, conn.isVideoMirroringSupported else { return }
        conn.automaticallyAdjustsVideoMirroring = false
        conn.isVideoMirrored = true
    }
}
