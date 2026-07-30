# CRC — controle o Mac com as mãos

App de menu bar para macOS que reconhece gestos de mão pela câmera e os transforma em comandos do sistema — 100% nativo, sem dependências externas.

> **Demo:** pinçe com os dedos para agarrar uma lente Liquid Glass sobre o feed da câmera; use as duas mãos para escalar e girar.

<!-- adicione aqui um GIF de demo: ![demo](docs/demo.gif) -->

## Como funciona

Pipeline totalmente nativo, sem Python nem modelos externos:

```
AVFoundation (câmera VGA) → Vision (VNDetectHumanHandPoseRequest)
  → One Euro Filter → heurísticas geométricas de gesto → osascript
```

- **HandTracker** roda o Vision a ~15fps e entrega 21 pontos por mão (layout de índices compatível com o do MediaPipe: 0 = pulso, 4 = ponta do polegar, 8 = ponta do indicador…).
- **HandFilter** aplica um One Euro Filter ciente de confiança + rejeição de outliers, para tracking estável sem lag perceptível.
- **Gestures** reconhece pinça, apontar, punho, mão aberta e contagem de dedos por heurística geométrica pura, normalizada pelo tamanho da mão.
- **GestureSequencer** monta uma gramática de comandos: sequências ("A → B"), holds e combos de duas mãos. Gesto solto de uma mão nunca dispara comando — anti-acidente por design.
- **CommandDispatcher** mapeia comandos para AppleScript (volume, mídia etc.).

A janela de preview mostra o esqueleto das mãos e uma lente **Liquid Glass** (glassEffect nativo do macOS 26) manipulável por gestos: 1 pinça move, 2 pinças escalam e giram.

## Requisitos

- macOS 26.0+
- Xcode 26 (SDK do macOS 26 — o `glassEffect` não compila em versões anteriores)
- Permissão de câmera (o sistema pede na primeira execução)

## Build

```bash
xcodebuild -project CRC/CRC.xcodeproj -scheme CRC -configuration Debug build
```

Ou abra `CRC/CRC.xcodeproj` no Xcode e rode o scheme `CRC`. O app vive na barra de menu (sem Dock); o preview é opcional, aberto pelo menu.

## Gestos

| Gesto | Ação |
|---|---|
| 1 pinça | agarra e move a lente |
| 2 pinças | escala (afastar/aproximar) e rotação |
| Sequências / holds / combos de duas mãos | comandos do sistema (configuráveis em `GestureCommands.swift`) |

Novos comandos = nova entrada no dicionário `bindings` do `CommandDispatcher`.

## Qualidade de tracking

`analyze_tracking.py` é uma ferramenta offline (Python, só para desenvolvimento — o app não depende dela) que analisa gravações do MetricsRecorder: jitter, latência do filtro, teleportes e histerese da pinça.

## Licença

[MIT](LICENSE)
