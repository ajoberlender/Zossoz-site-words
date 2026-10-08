#!/usr/bin/env python
"""Render each "<sound> as in <word>." script and cut out just the sound.

Run with voice-studio's interpreter:

    ~/voice-studio/.venv/bin/python make_clips.py            # everything
    ~/voice-studio/.venv/bin/python make_clips.py letter-a digraph-ai
    ~/voice-studio/.venv/bin/python make_clips.py --seeds 8  # try more takes

A lone phoneme makes the model near-silent, so each script speaks a whole
sentence. This renders it and has Whisper time the words. The sound is
everything before "as in": the cut goes at the quietest point just before "in".
Then it trims, fades, and normalises to -3 dB peak, mono 44.1 kHz.
A take is accepted only if Whisper heard "... in <word>"; otherwise the next
seed is tried.

Output (next to this file):
    clips/<name>.wav/.m4a the finished sound, ready for ios/.../Sounds/
    clips/full/<name>.wav the whole rendered sentence, to listen to when a cut is wrong
    clips/report.txt      one line per clip; REVIEW marks the ones to listen to
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf

sys.path.insert(0, str(Path.home() / "voice-studio"))
from voicestudio import voices as voicelib  # noqa: E402
from voicestudio.config import SAMPLE_RATE, RenderSettings  # noqa: E402
from voicestudio.engine import Engine  # noqa: E402

HERE = Path(__file__).parent
OUT = HERE / "clips"
FRAME = 0.005  # seconds per envelope frame
# Length targets from the recording scripts: (min, max) seconds.
CONTINUOUS = (0.6, 1.0)
STOP = (0.2, 0.5)


def spoken_line(path: Path) -> tuple[str, str]:
    """(voice, sentence) from a script: the @voice name and the one spoken line."""
    voice, line = "", ""
    for raw in path.read_text().splitlines():
        s = raw.strip()
        if not s or s.startswith("#"):
            continue
        if s.startswith("@voice"):
            voice = s.split(None, 2)[2]
        elif not s.startswith("@"):
            line = s
    return voice, line


def kind_of(path: Path) -> str:
    m = re.search(r"^# Note: A stop sound", path.read_text(), re.M)
    return "stop" if m else "continuous"


def envelope(x: np.ndarray) -> np.ndarray:
    n = int(SAMPLE_RATE * FRAME)
    frames = len(x) // n
    e = np.sqrt((x[: frames * n].reshape(frames, n) ** 2).mean(1))
    return 20 * np.log10(e + 1e-9)


_asr = None


def words(x: np.ndarray) -> list[tuple[str, float, float]]:
    """Whisper word timings for a 24 kHz mono array."""
    global _asr
    import librosa
    import torch
    from transformers import pipeline

    if _asr is None:
        _asr = pipeline(
            "automatic-speech-recognition",
            model="openai/whisper-large-v3-turbo",
            device="mps" if torch.backends.mps.is_available() else "cpu",
            dtype=torch.float16,
        )
    y = librosa.resample(x, orig_sr=SAMPLE_RATE, target_sr=16000)
    r = _asr({"raw": y, "sampling_rate": 16000}, return_timestamps="word", generate_kwargs={"language": "en"})
    return [(c["text"].strip().lower().strip(".,!?"), c["timestamp"][0], c["timestamp"][1]) for c in r["chunks"]]


def cut(x: np.ndarray, example: str) -> tuple[int, int] | None:
    """Sample range of the sound before "as in <example>", or None if the take is unusable."""
    heard = words(x)
    names = [w[0] for w in heard]
    if "in" not in names or names[-1] != example.lower():
        return None
    t_in = heard[names.index("in")][1]

    db = envelope(x)
    if db.max() < -40:
        return None
    on = max(0, int(np.argmax(db > db.max() - 45)) - int(0.03 / FRAME))
    # Quietest point (30 ms smoothed) in the stretch where "as" has to be.
    k = int(0.03 / FRAME)
    sm = np.convolve(db, np.ones(k) / k, mode="same")
    lo = max(on + int(0.2 / FRAME), int((t_in - 0.5) / FRAME))
    hi = min(int((t_in - 0.08) / FRAME), len(sm) - 1)
    if hi <= lo:
        return None
    end = lo + int(np.argmin(sm[lo : hi + 1]))
    return int(on * FRAME * SAMPLE_RATE), int(end * FRAME * SAMPLE_RATE)


def finish(x: np.ndarray) -> np.ndarray:
    fade = int(0.012 * SAMPLE_RATE)
    x = x.copy()
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x * (10 ** (-3 / 20) / np.abs(x).max())


def save(x: np.ndarray, dest: Path) -> None:
    """dest.wav (mono 16-bit 44.1 kHz) and dest.m4a (192 kbps AAC) from the same samples."""
    import soxr

    y = soxr.resample(x, SAMPLE_RATE, 44100, quality="VHQ")
    sf.write(dest.with_suffix(".wav"), y, 44100, subtype="PCM_16")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", str(dest.with_suffix(".wav")), "-c:a", "aac", "-b:a", "192k", str(dest.with_suffix(".m4a"))],
        check=True,
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("names", nargs="*", help="e.g. letter-a digraph-ai (default: all)")
    ap.add_argument("--seeds", type=int, default=5, help="takes to try per sound")
    args = ap.parse_args()

    scripts = sorted(HERE.glob("*.txt"))
    if args.names:
        scripts = [p for p in scripts if p.stem in args.names]
    (OUT / "full").mkdir(parents=True, exist_ok=True)

    engine = Engine()
    loaded_cache: dict[str, tuple] = {}
    report: list[str] = []

    for path in scripts:
        voice, sentence = spoken_line(path)
        if voice not in loaded_cache:
            v = voicelib.load_voice(voice)
            loaded_cache[voice] = (v, voicelib.load_prompt(v))
        v, prompt = loaded_cache[voice]
        lo, hi = STOP if kind_of(path) == "stop" else CONTINUOUS

        best = None
        for seed in range(args.seeds):
            audio = engine.generate(
                [sentence],
                voice_clone_prompt=prompt,
                instruct=v.instruct,
                language=v.language,
                settings=RenderSettings(num_step=32, seed=seed, speed=v.speed),
            )[0]
            audio = np.asarray(audio, dtype=np.float32).reshape(-1)
            span = cut(audio, sentence.rstrip(".").split()[-1])
            if span is None:
                continue
            clip = audio[span[0] : span[1]]
            secs = len(clip) / SAMPLE_RATE
            # How loud the sound is next to the words after it. A big gap means the
            # model mumbled the phoneme, and normalising would only amplify hiss.
            rel = 20 * np.log10(np.abs(clip).max() / np.abs(audio).max() + 1e-9)
            if best is None or rel > best[4]:
                best = (seed, audio, clip[: int(hi * SAMPLE_RATE)], secs, rel)
            if rel >= -10 and secs >= lo * 0.7:
                break

        if best is None:
            report.append(f"REVIEW {path.stem:12} {sentence!r}: no take where Whisper heard the whole sentence")
            continue
        seed, audio, clip, secs, rel = best
        sf.write(OUT / "full" / f"{path.stem}.wav", audio, SAMPLE_RATE)
        save(finish(clip), OUT / path.stem)
        short, faint = secs < lo * 0.7, rel < -10
        flag = "REVIEW" if (short or faint) else "ok    "
        why = ""
        if short:
            why += f" short (target {lo}-{hi}s)"
        if faint:
            why += f" faint: {rel:.0f} dB under the rest of the sentence"
        if secs > hi:
            why += f" cut to {hi}s (was {secs:.2f}s)"
        secs = min(secs, hi)
        report.append(f"{flag} {path.stem:12} seed {seed}  {secs:.2f}s  {sentence}{why}")
        print(report[-1], flush=True)

    (OUT / "report.txt").write_text("\n".join(report) + "\n")
    print(f"\nwrote {OUT}/report.txt")


if __name__ == "__main__":
    main()
