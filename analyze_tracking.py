#!/usr/bin/env python3
"""Analisa gravações do CRC (crc-rec-*.json gerados pelo MetricsRecorder).

Uso:
    python3 analyze_tracking.py --still A.json --fast B.json [--pinch C.json]
    python3 analyze_tracking.py --selftest

Métricas:
  1. Jitter (--still): deslocamento euclidiano entre frames consecutivos, em px
     (normalizado × resolução real do frame), média e p95, para indexTip e wrist.
  2. Latência (--fast): atraso de grupo cru→filtrado via correlação cruzada no
     eixo dominante do movimento, lag convertido pra ms com o fps MEDIDO.
  3. Teleportes (--still): frames com salto > média + 3σ, com confidence e px.
  4. Pinça (--pinch, opcional): chaveamentos do limiar único 0.35 vs histerese 0.22/0.38.

Os quatro sinais comparados: cru, média móvel causal n=2, causal n=5, e o One Euro
GRAVADO pelo app (inclui a rejeição de outliers do HandFilter — é o que roda de verdade).
"""
import argparse
import json
import sys

import numpy as np

WRIST, THUMB_TIP, INDEX_TIP, MIDDLE_MCP = 0, 4, 8, 9
LANDMARKS = {"indexTip": INDEX_TIP, "wrist": WRIST}


def load(path):
    with open(path) as f:
        doc = json.load(f)
    t, dt, raw, filt, idx = [], [], [], [], []
    for i, fr in enumerate(doc["frames"]):
        if not fr["raw"]:  # frame sem mão detectada
            continue
        t.append(fr["t"])
        dt.append(fr["dt"])
        raw.append(fr["raw"][0])  # primeira mão
        filt.append(fr["filtered"][0])
        idx.append(i)
    dropped = len(doc["frames"]) - len(raw)
    if dropped:
        print(f"  aviso: {dropped} frames sem mão em {path}", file=sys.stderr)
    if len(raw) < 60:
        sys.exit(f"erro: só {len(raw)} frames com mão em {path} — regrave")
    return dict(t=np.array(t), dt=np.array(dt), W=doc["width"], H=doc["height"],
                raw=np.array(raw), filt=np.array(filt), idx=np.array(idx))  # (F, 21, 3)


def fps_measured(rec):
    d = rec["dt"][rec["dt"] > 0]
    return 1.0 / d.mean(), d.std() / d.mean()


def ffill(xy, conf):
    """Segura a última posição em frames com landmark ausente (como o app faz).
    Frames iniciais sem landmark recebem o primeiro valor válido (backfill) —
    senão o [0,0] do ponto ausente contamina as médias móveis."""
    out = xy.copy()
    valid = np.where(conf > 0)[0]
    if len(valid) and valid[0] > 0:
        out[:valid[0]] = out[valid[0]]
    for i in range(1, len(out)):
        if conf[i] <= 0:
            out[i] = out[i - 1]
    return out


def causal_ma(xy, n):
    """Média móvel CAUSAL (só passado), como rodaria em tempo real."""
    if n == 1:
        return xy.copy()
    out = np.empty_like(xy)
    for i in range(len(xy)):
        out[i] = xy[max(0, i - n + 1):i + 1].mean(axis=0)
    return out


def variants(rec, idx):
    conf = rec["raw"][:, idx, 2]
    raw = ffill(rec["raw"][:, idx, :2].astype(float), conf)
    return {
        "cru": raw,
        "MA n=2": causal_ma(raw, 2),
        "MA n=5": causal_ma(raw, 5),
        "One Euro (app)": rec["filt"][:, idx, :2].astype(float),
    }


def steps_px(xy, W, H):
    d = np.diff(xy, axis=0) * [W, H]
    return np.hypot(d[:, 0], d[:, 1])


def valid_steps(rec, trim=1.0):
    """Máscara de passos válidos: frames de captura consecutivos (sem buraco de
    tracking no meio) e fora do 1º segundo (mão ainda entrando em posição)."""
    return (np.diff(rec["idx"]) == 1) & (rec["t"][1:] >= trim)


def runs(rec, min_len=45):
    """Trechos contínuos (sem frame perdido) com pelo menos min_len frames."""
    breaks = np.where(np.diff(rec["idx"]) != 1)[0] + 1
    segs = np.split(np.arange(len(rec["idx"])), breaks)
    return sorted((s for s in segs if len(s) >= min_len), key=len, reverse=True)


def lag_frames(ref, sig):
    """Lag de sig vs ref em frames (correlação cruzada + interpolação parabólica)."""
    a = ref - ref.mean()
    b = sig - sig.mean()
    c = np.correlate(b, a, "full")
    k = int(np.argmax(c))
    if 0 < k < len(c) - 1:
        denom = c[k - 1] - 2 * c[k] + c[k + 1]
        if denom != 0:
            k += 0.5 * (c[k - 1] - c[k + 1]) / denom
    return k - (len(a) - 1)


def report_jitter(rec):
    ok = valid_steps(rec)
    print(f"\n== 1. JITTER (gravação A, px/frame, {ok.sum()} passos válidos — "
          "sem buracos de tracking, 1º segundo descartado) ==")
    print(f"{'filtro':<16}{'landmark':<10}{'média':>8}{'p95':>8}")
    for lname, idx in LANDMARKS.items():
        conf = rec["raw"][:, idx, 2]
        missing = int((conf <= 0).sum())
        if missing:
            print(f"  aviso: {lname} ausente em {missing} frames (segurados)", file=sys.stderr)
        for fname, xy in variants(rec, idx).items():
            s = steps_px(xy, rec["W"], rec["H"])[ok]
            print(f"{fname:<16}{lname:<10}{s.mean():>8.2f}{np.percentile(s, 95):>8.2f}")


def report_latency(rec):
    fps, cv = fps_measured(rec)
    print(f"\n== 2. LATÊNCIA (gravação B, fps medido = {fps:.1f}, cv dt = {cv:.0%}) ==")
    if cv > 0.25:
        print("  aviso: dt muito irregular — latência em ms fica menos confiável", file=sys.stderr)
    segs = runs(rec)
    if not segs:
        sys.exit("erro: nenhum trecho contínuo ≥ 45 frames — regrave B")
    total = sum(len(s) for s in segs)
    print(f"  {len(segs)} trechos contínuos ≥ 45 frames (total {total} frames, "
          f"{total / fps:.1f}s; maior = {len(segs[0])})")
    all_vs = variants(rec, INDEX_TIP)
    axis = int(np.argmax(all_vs["cru"].var(axis=0)))  # eixo dominante do movimento
    print(f"  eixo dominante: {'xy'[axis]}")
    print(f"{'filtro':<16}{'lag mediano':>12}{'lag (ms)':>10}{'faixa (ms)':>18}")
    for fname, xy in all_vs.items():
        lags = np.array([lag_frames(all_vs["cru"][s, axis], xy[s, axis]) for s in segs])
        med = np.median(lags) * 1000 / fps
        lo, hi = lags.min() * 1000 / fps, lags.max() * 1000 / fps
        print(f"{fname:<16}{np.median(lags):>12.2f}{med:>10.1f}{f'{lo:.1f} … {hi:.1f}':>18}")
        if fname == "cru" and abs(np.median(lags)) > 0.1:
            print("  aviso: lag do cru vs ele mesmo devia ser 0 — algo estranho", file=sys.stderr)
        if med < -0.5 * 1000 / fps:
            print(f"  aviso: lag negativo em {fname} — não faz sentido físico, desconfie", file=sys.stderr)


def report_teleports(rec):
    print("\n== 3. TELEPORTES (gravação A, salto > média + 3σ, indexTip cru) ==")
    idx = INDEX_TIP
    xy = rec["raw"][:, idx, :2].astype(float)
    conf = rec["raw"][:, idx, 2]
    ok = valid_steps(rec)
    s = np.where(ok, steps_px(ffill(xy, conf), rec["W"], rec["H"]), np.nan)
    thr = np.nanmean(s) + 3 * np.nanstd(s)
    hits = np.where(s > thr)[0] + 1
    print(f"limiar: {thr:.2f} px ({len(hits)} frames acima; 1º segundo e buracos excluídos)")
    for i in hits[:10]:
        print(f"  frame {rec['idx'][i]}: salto {s[i - 1]:.1f} px, confidence {conf[i]:.2f}")
    if len(hits) > 10:
        print(f"  … +{len(hits) - 10} omitidos")
    if not len(hits):
        print("  nenhum — ou a gravação está limpa, ou 20s foi pouco pra capturar um")


def report_pinch(rec):
    print("\n== 4. PINÇA (gravação C, chaveamentos em ~20s) ==")
    for src in ("raw", "filt"):
        h = rec[src]
        d48 = np.hypot(*(h[:, THUMB_TIP, :2] - h[:, INDEX_TIP, :2]).T)
        d09 = np.hypot(*(h[:, WRIST, :2] - h[:, MIDDLE_MCP, :2]).T)
        r = d48 / np.maximum(d09, 1e-4)
        single = int((np.diff(r < 0.35) != 0).sum())
        state, hyst = False, 0
        for v in r:
            if not state and v < 0.22:
                state, hyst = True, hyst + 1
            elif state and v > 0.38:
                state, hyst = False, hyst + 1
        label = "cru" if src == "raw" else "filtrado"
        print(f"{label:<10} limiar único 0.35: {single:>3} chaveamentos | histerese 0.22/0.38: {hyst:>3}")


def one_euro(xy, dts, min_cutoff=2.0, beta=0.05, d_cutoff=1.0):
    """One Euro offline, mesma matemática do HandFilter.swift (sem a rejeição
    de outliers — irrelevante pra sinais contínuos com mão presente)."""
    out = np.empty_like(xy)
    x_hat = xy[0].copy()
    dx_hat = np.zeros(2)
    out[0] = xy[0]
    for i in range(1, len(xy)):
        te = max(dts[i], 1e-3)
        dx = (xy[i] - xy[i - 1]) / te
        ad = 1 / (1 + 1 / (2 * np.pi * d_cutoff * te))
        dx_hat = ad * dx + (1 - ad) * dx_hat
        cutoff = min_cutoff + beta * np.abs(dx_hat)
        a = 1 / (1 + 1 / (2 * np.pi * cutoff * te))
        x_hat = a * xy[i] + (1 - a) * x_hat
        out[i] = x_hat
    return out


def report_sweep(rec_still, rec_fast):
    """Varre (minCutoff, beta) sobre os dados gravados: jitter da A, latência da B."""
    fps, _ = fps_measured(rec_fast)
    ok = valid_steps(rec_still)
    conf_a = rec_still["raw"][:, INDEX_TIP, 2]
    raw_a = ffill(rec_still["raw"][:, INDEX_TIP, :2].astype(float), conf_a)
    run = runs(rec_fast)[0]
    conf_b = rec_fast["raw"][:, INDEX_TIP, 2]
    raw_b = ffill(rec_fast["raw"][:, INDEX_TIP, :2].astype(float), conf_b)[run]
    dts_b = rec_fast["dt"][run]
    axis = int(np.argmax(raw_b.var(axis=0)))

    print("\n== SWEEP One Euro (indexTip; jitter da A, latência da B) ==")
    print(f"{'minCutoff':>10}{'beta':>7}{'jitter méd':>11}{'jitter p95':>11}{'lag (ms)':>10}")
    # beta pequeno mal abre o cutoff em coordenadas normalizadas (velocidade ~1-2 u/s);
    # a faixa útil medida nos dados é 1-30.
    for mc in (1.0, 2.0):
        for b in (0.05, 0.3, 1.0, 3.0, 10.0, 30.0):
            fa = one_euro(raw_a, rec_still["dt"], mc, b)
            s = steps_px(fa, rec_still["W"], rec_still["H"])[ok]
            fb = one_euro(raw_b, dts_b, mc, b)
            lag = lag_frames(raw_b[:, axis], fb[:, axis]) * 1000 / fps
            mark = "  ← atual" if (mc, b) == (2.0, 0.05) else ""
            print(f"{mc:>10.1f}{b:>7.2f}{s.mean():>11.2f}{np.percentile(s, 95):>11.2f}{lag:>10.1f}{mark}")

    # Sanidade: offline com os parâmetros atuais deve bater com o filtro do app.
    app = rec_still["filt"][:, INDEX_TIP, :2].astype(float)
    s_app = steps_px(app, rec_still["W"], rec_still["H"])[ok]
    print(f"  sanidade: One Euro do app gravado = jitter {s_app.mean():.2f} px "
          "(compare com a linha 2.0/0.05 — diferença grande = implementação offline errada)")


def selftest():
    t = np.arange(0, 3, 1 / 30)
    x = np.sin(2 * np.pi * t)
    sig = np.stack([x, np.zeros_like(x)], axis=1)
    lag = lag_frames(x, causal_ma(sig, 5)[:, 0])
    assert 1.5 < lag < 2.5, lag  # MA causal n=5 → lag teórico (n-1)/2 = 2 frames
    assert abs(lag_frames(x, x)) < 1e-6
    conf = np.ones(len(x))
    conf[10] = 0
    ff = ffill(sig.copy(), conf)
    assert (ff[10] == ff[9]).all()
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--still", help="gravação A: mão imóvel")
    ap.add_argument("--fast", help="gravação B: movimento lateral rápido")
    ap.add_argument("--pinch", help="gravação C: pinça perto do limiar")
    ap.add_argument("--sweep", action="store_true",
                    help="varre minCutoff × beta do One Euro (exige --still e --fast)")
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args()
    if args.selftest:
        return selftest()
    if args.sweep:
        if not (args.still and args.fast):
            ap.error("--sweep exige --still e --fast")
        return report_sweep(load(args.still), load(args.fast))
    if not (args.still or args.fast or args.pinch):
        ap.error("passe pelo menos uma gravação (--still/--fast/--pinch)")
    if args.still:
        rec = load(args.still)
        fps, _ = fps_measured(rec)
        print(f"A: {len(rec['t'])} frames, {rec['t'][-1]:.1f}s, fps medido {fps:.1f}, {rec['W']}x{rec['H']}")
        report_jitter(rec)
        report_teleports(rec)
    if args.fast:
        rec = load(args.fast)
        report_latency(rec)
    if args.pinch:
        report_pinch(load(args.pinch))


if __name__ == "__main__":
    main()
