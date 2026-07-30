//
//  GestureCommands.swift
//  CRC
//
//  Gramática de comandos sobre os gestos básicos:
//   • token = gesto estável por 0.35s (uma mão) OU combo "E:x + D:y" (duas mãos)
//   • sequência: token A → token B em até 2s  → comando "A → B"
//   • hold: token mantido 1.2s               → comando "X (hold)"
//   • combo de duas mãos dispara sozinho
//  Gesto solto de uma mão NUNCA dispara — só compõe sequência (anti-acidente).
//

import Foundation
import Combine

final class GestureSequencer: ObservableObject {
    @Published private(set) var lastCommand = ""
    @Published private(set) var pendingDisplay = ""  // primeiro passo da sequência, pra UI

    // Botões de calibração da gramática:
    private let stableTime = 0.35  // gesto precisa ficar parado isso pra virar token
    private let holdTime = 1.2     // token mantido isso vira "(hold)"
    private let seqWindow = 2.0    // janela máxima entre os dois passos da sequência

    private var currentToken = ""
    private var tokenStart = 0.0
    private var registered = false
    private var holdFired = false
    private var pendingToken = ""
    private var pendingTime = 0.0

    func update(hands: [Hand], chirality: [String], now: Double) {
        let token = Self.token(hands: hands, chirality: chirality)

        if token != currentToken {
            currentToken = token
            tokenStart = now
            registered = false
            holdFired = false
        }

        if !token.isEmpty {
            let dur = now - tokenStart
            if !registered && dur >= stableTime {
                registered = true
                register(token, now: now)
            }
            if registered && !holdFired && dur >= holdTime {
                holdFired = true
                pendingToken = ""  // hold consome a sequência pendente
                fire("\(token) (hold)")
            }
        }

        // Sequência expirou sem segundo passo.
        if !pendingToken.isEmpty && now - pendingTime > seqWindow {
            pendingToken = ""
        }
        pendingDisplay = pendingToken
    }

    private func register(_ token: String, now: Double) {
        // Combo de duas mãos dispara sozinho.
        if token.contains("+") {
            pendingToken = ""
            fire(token)
            return
        }
        // Uma mão: compõe sequência.
        if !pendingToken.isEmpty && pendingToken != token && now - pendingTime <= seqWindow {
            let cmd = "\(pendingToken) → \(token)"
            pendingToken = ""
            fire(cmd)
        } else {
            pendingToken = token
            pendingTime = now
        }
    }

    private func fire(_ command: String) {
        lastCommand = command
        print("[CMD] \(command)")
        CommandDispatcher.run(command)
    }

    /// Estado atual das mãos → token ("" se nada reconhecível).
    static func token(hands: [Hand], chirality: [String]) -> String {
        let gestures = hands.map { Gesture.name(for: $0) }
        let valid = gestures.enumerated().filter { !$0.element.isEmpty }
        guard !valid.isEmpty else { return "" }
        if valid.count >= 2 && chirality.count == hands.count {
            return valid.map { "\(chirality[$0.offset]):\($0.element)" }.sorted().joined(separator: " + ")
        }
        return valid[0].element
    }
}

/// Liga comandos a ações. Sem binding = só log (o print acima já registra tudo).
/// Volume via osascript não requer permissão de Acessibilidade.
enum CommandDispatcher {
    private static let bindings: [String: String] = [
        "apontar → mão aberta": "set volume output volume (output volume of (get volume settings)) + 10",
        "mão aberta → apontar": "set volume output volume (output volume of (get volume settings)) - 10",
        "pinça (hold)": "set volume output muted not (output muted of (get volume settings))",
    ]

    static func run(_ command: String) {
        guard let script = bindings[command] else { return }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", script]
            try? p.run()
        }
    }
}
