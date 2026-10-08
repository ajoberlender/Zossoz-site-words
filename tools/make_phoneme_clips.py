#!/usr/bin/env python3
"""Regenerates ios/SightWords/Resources/Sounds/*.m4a: the isolated letter / digraph sounds.

Needs espeak-ng and ffmpeg. These are synthesized stand-ins: to use a real voice, record each sound and
save it over the matching file (same name, .m4a). The app plays whatever is in that folder.
Run from the repo root:  python3 tools/make_phoneme_clips.py   (writes to ./out, then copy into Resources/Sounds)
"""
import subprocess, os, json, re
# key -> (espeak phonemes, continuous?)
S = {
 "letter-s":("s",1),"letter-a":("a",1),"letter-t":("t@",0),"letter-p":("p@",0),"letter-i":("I",1),"letter-n":("n",1),
 "letter-m":("m",1),"letter-d":("d@",0),"letter-o":("0",1),"letter-g":("g@",0),"letter-c":("k@",0),"letter-k":("k@",0),
 "letter-e":("E",1),"letter-u":("V",1),"letter-r":("r",1),"letter-h":("h@",0),"letter-b":("b@",0),"letter-f":("f",1),
 "letter-l":("l",1),"letter-j":("dZ@",0),"letter-v":("v",1),"letter-w":("w@",0),"letter-x":("ks",0),"letter-y":("j@",0),
 "letter-z":("z",1),"letter-q":("kw@",0),
 "digraph-sh":("S",1),"digraph-ch":("tS@",0),"digraph-th":("T",1),"digraph-wh":("w@",0),"digraph-ck":("k@",0),
 "digraph-ng":("N",1),"digraph-qu":("kw@",0),"digraph-ee":("i:",1),"digraph-ai":("eI",1),"digraph-oa":("oU",1),
 "digraph-oo":("u:",1),"digraph-ar":("A@",1),
}
os.makedirs("out",exist_ok=True)
for k,(ph,cont) in S.items():
    wav=f"{k}.wav"
    def synth(p):
        subprocess.run(["espeak-ng","-v","en-us","-s","80","-p","50","-a","180","-w",wav,f"[[{p}]]"],check=True)
        o=subprocess.run(["ffmpeg","-hide_banner","-i",wav,"-af","volumedetect","-f","null","-"],capture_output=True,text=True).stderr
        m=re.search(r"max_volume: (-?[\d.]+) dB",o)
        return float(m.group(1)) if m else -99
    if synth(ph) < -50:
        print("SILENT",k,ph,"-> adding schwa"); ph=ph+"@"; cont=0
        synth(ph)
    dur=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",wav]))
    target = 0.9 if cont else 0.0
    filt=["silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02","areverse","silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.02","areverse"]
    # stretch continuous sounds to ~0.9s (atempo >= 0.5 per stage)
    import math
    trimmed=f"{k}.t.wav"
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",wav,"-af",",".join(filt),trimmed],check=True)
    d=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",trimmed]))
    af=[]
    if cont and d<target:
        r=d/target
        while r<0.5: af.append("atempo=0.5"); r/=0.5
        af.append(f"atempo={r:.3f}")
    af+=["afade=t=in:d=0.01","loudnorm=I=-16:TP=-1.5:LRA=7"]
    subprocess.run(["ffmpeg","-y","-loglevel","error","-i",trimmed,"-af",",".join(af),"-ar","44100","-ac","1","-c:a","aac","-b:a","64k",f"out/{k}.m4a"],check=True)
    d2=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",f"out/{k}.m4a"]))
    print(k,ph,round(dur,2),"->",round(d2,2))
