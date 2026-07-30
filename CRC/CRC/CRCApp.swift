//
//  CRCApp.swift
//  CRC
//
//  App de menu bar (LSUIElement): roda de fundo sem janela nem Dock.
//  O pipeline câmera→Vision→gestos vive no AppModel, independente de UI.
//  Preview é uma janela opcional pra debug.
//

import SwiftUI
import Combine
import QuartzCore

@MainActor
final class AppModel: ObservableObject {
    let camera = CameraCapture()
    let tracker = HandTracker()
    let lens = GlassInteraction()
    private var cancellable: AnyCancellable?

    init() {
        camera.onPixelBuffer = { [tracker] pb in tracker.process(pb) }
        cancellable = tracker.$hands
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hands in
                self?.lens.update(hands: hands, now: CACurrentMediaTime())
            }
        tracker.start()
        camera.requestAndStart()
    }
}

@main
struct CRCApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: "hand.raised.fill")
        }

        Window("CRC Preview", id: "preview") {
            ContentView(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(.presented)
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AppModel
    @ObservedObject var lens: GlassInteraction
    @ObservedObject var tracker: HandTracker
    @Environment(\.openWindow) private var openWindow

    init(model: AppModel) {
        self.model = model
        self.lens = model.lens
        self.tracker = model.tracker
    }

    var body: some View {
        Text(lens.status)
        Divider()
        Button("Mostrar preview") { openWindow(id: "preview") }
        Button("Formato paisagem (16:9)") { setPreviewSize(width: 960, height: 540) }
        Button("Formato vertical (Reels 9:16)") { setPreviewSize(width: 506, height: 900) }
        Divider()
        Button(tracker.recordingActive ? "Gravando métricas…" : "Gravar métricas (20s)") {
            tracker.startMetricsRecording()
        }
        .disabled(tracker.recordingActive)
        Divider()
        Button("Sair") { NSApp.terminate(nil) }
    }

    /// Redimensiona a janela de preview mantendo o topo no lugar.
    /// O preview é aspectFill: em 9:16 a câmera recorta as laterais sozinha.
    private func setPreviewSize(width: CGFloat, height: CGFloat) {
        guard let win = NSApp.windows.first(where: { $0.title == "CRC Preview" }) else {
            openWindow(id: "preview")
            return
        }
        var f = win.frame
        f.origin.y -= height - f.height
        f.size = NSSize(width: width, height: height)
        win.setFrame(f, display: true, animate: true)
        win.makeKeyAndOrderFront(nil)
    }
}
