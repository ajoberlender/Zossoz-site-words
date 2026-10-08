#!/usr/bin/env python
"""Render alternative spellings for sounds that came out wrong, to audition by ear.

    ~/voice-studio/.venv/bin/python try_variants.py            # all four
    ~/voice-studio/.venv/bin/python try_variants.py digraph-th

Writes clips/try/<name>-<variant>-s<seed>-full.wav (the whole sentence) and
-cut.wav (just the sound), and prints what Whisper heard, which is a hint and
not a verdict. Listen, then put the winning spelling in the script.
"""
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

import make_clips as m
from voicestudio import voices as voicelib
from voicestudio.config import SAMPLE_RATE, RenderSettings
from voicestudio.engine import Engine

VARIANTS = {
    "digraph-th": ("thin", ["[TH AH1]", "[TH UH1]", "[TH ER1]", "[TH AH0] [TH AH0]"]),
    "digraph-oo": ("moon", ["[UW2]", "[UW1 UW1]", "[W UW1]", "[UW0]"]),
    "digraph-ng": ("ring", ["[AH1 NG]", "[IH1 NG]", "[NG AA1]", "[NG AH0]"]),
    "letter-u": ("umbrella", ["[AH2]", "[AH1 AH1]", "[AH0 AH1]", "[HH AH1]"]),
}
SEEDS = 3

names = sys.argv[1:] or list(VARIANTS)
out = m.OUT / "try"
out.mkdir(parents=True, exist_ok=True)
engine = Engine()
v = voicelib.load_voice("AJ")
prompt = voicelib.load_prompt(v)

for name in names:
    word, spellings = VARIANTS[name]
    for i, ph in enumerate(spellings, 1):
        for seed in range(SEEDS):
            text = f"{ph} as in {word}."
            a = engine.generate([text], voice_clone_prompt=prompt, instruct=v.instruct,
                                language=v.language, settings=RenderSettings(num_step=32, seed=seed, speed=v.speed))[0]
            a = np.asarray(a, dtype=np.float32).reshape(-1)
            tag = f"{name}-{i}-s{seed}"
            sf.write(out / f"{tag}-full.wav", a / np.abs(a).max() * 0.7, SAMPLE_RATE)
            heard = " ".join(w[0] for w in m.words(a))
            span = m.cut(a, word)
            if span:
                m.save(m.finish(a[span[0]:span[1]][: int(1.0 * SAMPLE_RATE)]), out / f"{tag}-cut")
            print(f"{tag:22} {text:34} heard: {heard!r}{'' if span else '  (no cut)'}", flush=True)
