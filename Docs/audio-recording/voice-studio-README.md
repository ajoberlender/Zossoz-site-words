# voice-studio scripts for the letter and digraph sounds

The scripts are in [`voice-studio/`](voice-studio). One `.txt` script per sound (38). Each contains only the phonemes to generate, in ARPAbet brackets, plus `#`
comment lines (never spoken) with the guidance from the human recording scripts in the parent folder. **Do not feed the
`.md` files in the parent folder to voice-studio: they are instructions for a person and would be read aloud.**
This README sits next to the `voice-studio/` folder, not inside it, so `vs batch` only sees the scripts.

## Run

```bash
vs say "[AE1]" -v "AJ"                          # hear one raw phoneme (no lexicon, no normalisation)
vs batch Docs/audio-recording/voice-studio      # render every script; each script's name is the output name
```

The scripts use `@voice NARRATOR AJ`. If your voice has another name, change it in all files:

```bash
sed -i '' 's/@voice NARRATOR AJ/@voice NARRATOR YourVoice/' Docs/audio-recording/voice-studio/*.txt   # macOS
```

(or pass `--cast "NARRATOR=YourVoice"` and delete the `@voice` line). `@gap 0` stops silence being added after the line.

## Output names → the app

Keep the output names exactly as the scripts are named (`letter-a`, `digraph-ai`, …). Export `.m4a` or `.wav`
(mono, 44.1 kHz), then copy the files into `ios/SightWords/Resources/Sounds/`. See `../README.md` for the full
format notes. The app prefers `.wav`/`.mp3`/`.caf`/`.aac` over the old `.m4a` placeholders.

## Limits to expect

- **Every bracket group needs a vowel.** So a bare `[S]` or `[T]` is invalid. Stop sounds and consonants are
  written as consonant + short schwa (`[T AH0]`, `[S AH0]`), which leaves a small "uh". For the sounds you
  should *hold* (s, f, m, n, l, r, v, z, sh, th), listen for the vowel and trim it in your editor if it's audible.
- **`h`** is `[HH AA1]` because HH only works before a full back vowel. It will sound like "hah"; trim or
  re-record by hand if it's too wordlike.
- **`ng`** is `[AH0 NG]` (the vowel has to come first); cut the leading "uh" in your editor.
- **Hold length.** Generation will likely give short clips rather than a 0.6–1.0 s held sound. Check the
  vowels and continuous consonants by ear and stretch or loop them in an editor if they're too short.
- ARPAbet does have `CH` and `JH`, so `ch` and `j` are fine. Sounds outside English phonemes aren't needed here.

## Phoneme table

| File | Line | | File | Line |
|---|---|---|---|---|
| letter-s | `[S AH0]` | | digraph-sh | `[SH AH0]` |
| letter-a | `[AE1]` | | digraph-ch | `[CH AH0]` |
| letter-t | `[T AH0]` | | digraph-th | `[TH AH0]` |
| letter-p | `[P AH0]` | | digraph-wh | `[W AH0]` |
| letter-i | `[IH1]` | | digraph-ck | `[K AH0]` |
| letter-n | `[N AH0]` | | digraph-ng | `[AH0 NG]` |
| letter-m | `[M AH0]` | | digraph-qu | `[K W AH0]` |
| letter-d | `[D AH0]` | | digraph-ee | `[IY1]` |
| letter-o | `[AA1]` | | digraph-ai | `[EY1]` |
| letter-g | `[G AH0]` | | digraph-oa | `[OW1]` |
| letter-c | `[K AH0]` | | digraph-oo | `[UW1]` |
| letter-k | `[K AH0]` | | digraph-ar | `[AA1 R]` |
| letter-e | `[EH1]` | | | |
| letter-u | `[AH1]` | | | |
| letter-r | `[R AH0]` | | | |
| letter-h | `[HH AA1]` | | | |
| letter-b | `[B AH0]` | | | |
| letter-f | `[F AH0]` | | | |
| letter-l | `[L AH0]` | | | |
| letter-j | `[JH AH0]` | | | |
| letter-v | `[V AH0]` | | | |
| letter-w | `[W AH0]` | | | |
| letter-x | `[K S AH0]` | | | |
| letter-y | `[Y AH0]` | | | |
| letter-z | `[Z AH0]` | | | |
| letter-q | `[K W AH0]` | | | |
