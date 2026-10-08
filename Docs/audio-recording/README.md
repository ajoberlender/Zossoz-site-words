# Recording the letter and digraph sounds

The app plays a short recording whenever it needs to say a letter or digraph sound (intro cards, “which
letter makes this sound?”, “sound it out”, flashcards, and the “That's *sound*, like in *word*” feedback).
Speech synthesis can't say a bare sound properly (it says “ess ess” for S), so these recordings are the real
fix. There are **38 files**: 26 letters and 12 digraphs. Each has its own script in this folder.

## What format?

**Easiest: `.m4a` (AAC), mono, 44.1 kHz.** These also work as-is: `.wav`, `.mp3`, `.caf`, `.aac`.
If your recording app exports something else (for example `.flac` or `.ogg`), convert it to `.m4a` or `.wav` first.

| Setting | Use |
|---|---|
| Channels | **Mono** (one channel) |
| Sample rate | 44.1 kHz (48 kHz also fine) |
| Bit depth / quality | 16-bit for `.wav`; about 64 kbps or higher for `.m4a` / `.mp3` |
| Length | Continuous sounds 0.6–1.0 s; stop sounds 0.2–0.5 s (see each script) |
| Loudness | Peak around −3 dB; keep every file at a similar volume |
| Silence | Trim the start to under about 50 ms; end cleanly |

## File names (important)

Name each file **exactly** as shown, in lower case, with no spaces: `letter-s.m4a`, `digraph-sh.m4a`, and so
on. The app finds a recording by name, so a different name means it's never played.

## Where to put the files

Copy them into **`ios/SightWords/Resources/Sounds/`**. They replace the placeholder (synthesized) clips there:

- A file with the same name **and** the same type (for example `letter-s.m4a`) simply overwrites the old one.
- If you save as `.wav`, `.mp3`, `.caf` or `.aac`, the app prefers it over the old `.m4a`, so you can leave the old files in place while you work.
- Any sound you haven't recorded yet keeps using the placeholder, so you can do these a few at a time.

Then, in Xcode, make sure the **Sounds** folder is in the SightWords target (drag the folder in and tick
“Add to targets: SightWords”), and rebuild.

## Recording tips

- A quiet room with soft furnishings; no fan, fridge or traffic.
- Mouth about a hand-span (15 cm) from the microphone, slightly off to the side to avoid breath pops, or use a pop filter.
- Use one voice and one distance for all files. A warm, clear voice works best for young children.
- Say the sound **by itself, not as a word**. “Sss” not “ess”; “k” not “kuh-oo”; “kw” not “queue”.
- For **stop** sounds (t, p, k, d, b, g, j, ch…) a tiny, clipped “uh” after the consonant is unavoidable. Keep it as short as you can, so “t” doesn't become “tuh”.
- For **continuous** sounds (s, f, m, n, l, r, v, z, sh, th, ng and the vowels), hold them steady, at an even volume.
- Record each sound 3 times and keep the best. Listen on phone speakers, since that's where children will hear them.

## Checklist

| # | File to record | Sound | Example word | Type | Script | Done |
|---|---|---|---|---|---|---|
| 1 | `letter-s` | /s/ | snake | continuous | [letter-s.md](letter-s.md) | ☐ |
| 2 | `letter-a` | /æ/ | apple | continuous | [letter-a.md](letter-a.md) | ☐ |
| 3 | `letter-t` | /t/ | tiger | stop | [letter-t.md](letter-t.md) | ☐ |
| 4 | `letter-p` | /p/ | penguin | stop | [letter-p.md](letter-p.md) | ☐ |
| 5 | `letter-i` | /ɪ/ | iguana | continuous | [letter-i.md](letter-i.md) | ☐ |
| 6 | `letter-n` | /n/ | nose | continuous | [letter-n.md](letter-n.md) | ☐ |
| 7 | `letter-m` | /m/ | moon | continuous | [letter-m.md](letter-m.md) | ☐ |
| 8 | `letter-d` | /d/ | dog | stop | [letter-d.md](letter-d.md) | ☐ |
| 9 | `letter-o` | /ɑ/ | octopus | continuous | [letter-o.md](letter-o.md) | ☐ |
| 10 | `letter-g` | /g/ | goat | stop | [letter-g.md](letter-g.md) | ☐ |
| 11 | `letter-c` | /k/ | cat | stop | [letter-c.md](letter-c.md) | ☐ |
| 12 | `letter-k` | /k/ | key | stop | [letter-k.md](letter-k.md) | ☐ |
| 13 | `letter-e` | /ɛ/ | egg | continuous | [letter-e.md](letter-e.md) | ☐ |
| 14 | `letter-u` | /ʌ/ | umbrella | continuous | [letter-u.md](letter-u.md) | ☐ |
| 15 | `letter-r` | /r/ | rainbow | continuous | [letter-r.md](letter-r.md) | ☐ |
| 16 | `letter-h` | /h/ | hat | stop | [letter-h.md](letter-h.md) | ☐ |
| 17 | `letter-b` | /b/ | bear | stop | [letter-b.md](letter-b.md) | ☐ |
| 18 | `letter-f` | /f/ | fish | continuous | [letter-f.md](letter-f.md) | ☐ |
| 19 | `letter-l` | /l/ | lion | continuous | [letter-l.md](letter-l.md) | ☐ |
| 20 | `letter-j` | /dʒ/ | juice | stop | [letter-j.md](letter-j.md) | ☐ |
| 21 | `letter-v` | /v/ | violin | continuous | [letter-v.md](letter-v.md) | ☐ |
| 22 | `letter-w` | /w/ | whale | stop | [letter-w.md](letter-w.md) | ☐ |
| 23 | `letter-x` | /ks/ | fox | stop | [letter-x.md](letter-x.md) | ☐ |
| 24 | `letter-y` | /j/ | yo-yo | stop | [letter-y.md](letter-y.md) | ☐ |
| 25 | `letter-z` | /z/ | zebra | continuous | [letter-z.md](letter-z.md) | ☐ |
| 26 | `letter-q` | /kw/ | queen | stop | [letter-q.md](letter-q.md) | ☐ |
| 27 | `digraph-sh` | /ʃ/ | ship | continuous | [digraph-sh.md](digraph-sh.md) | ☐ |
| 28 | `digraph-ch` | /tʃ/ | chip | stop | [digraph-ch.md](digraph-ch.md) | ☐ |
| 29 | `digraph-th` | /θ/ | thin | continuous | [digraph-th.md](digraph-th.md) | ☐ |
| 30 | `digraph-wh` | /w/ | whale | stop | [digraph-wh.md](digraph-wh.md) | ☐ |
| 31 | `digraph-ck` | /k/ | duck | stop | [digraph-ck.md](digraph-ck.md) | ☐ |
| 32 | `digraph-ng` | /ŋ/ | ring | continuous | [digraph-ng.md](digraph-ng.md) | ☐ |
| 33 | `digraph-qu` | /kw/ | queen | stop | [digraph-qu.md](digraph-qu.md) | ☐ |
| 34 | `digraph-ee` | /i/ | bee | continuous | [digraph-ee.md](digraph-ee.md) | ☐ |
| 35 | `digraph-ai` | /eɪ/ | train | continuous | [digraph-ai.md](digraph-ai.md) | ☐ |
| 36 | `digraph-oa` | /oʊ/ | goat | continuous | [digraph-oa.md](digraph-oa.md) | ☐ |
| 37 | `digraph-oo` | /u/ | moon | continuous | [digraph-oo.md](digraph-oo.md) | ☐ |
| 38 | `digraph-ar` | /ɑr/ | star | continuous | [digraph-ar.md](digraph-ar.md) | ☐ |

