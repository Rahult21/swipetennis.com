#!/usr/bin/env python3
"""Prepare a real recorded tennis forehand; no oscillators or synthesized tones.
Source and CC0 provenance: AudioSources/README.md. Python standard library only.
"""
from pathlib import Path
import array
import math
import sys
import wave

ROOT = Path(__file__).resolve().parent
with wave.open(str(ROOT / "AudioSources/tennis-forehand.wav")) as source:
    assert source.getnchannels() == 1 and source.getsampwidth() == 2
    rate = source.getframerate()
    samples = array.array("h", source.readframes(source.getnframes()))
    if sys.byteorder != "little":
        samples.byteswap()

# Isolate one real forehand contact. Other hits, traffic and wind stay out of the app.
start, end = round(0.121 * rate), round(0.321 * rate)
values = [v / 32768 for v in samples[start:end]]
# Gentle DC/wind removal; preserve the recorded string/felt transient and natural decay.
pole = math.exp(-2 * math.pi * 65 / rate)
previous_in = previous_out = 0.0
for i, value in enumerate(values):
    filtered = value - previous_in + pole * previous_out
    previous_in, previous_out = value, filtered
    attack = min(1, i / max(1, rate * 0.0005))
    release = min(1, (len(values) - 1 - i) / max(1, rate * 0.055))
    values[i] = filtered * attack * release
gain = 0.8 / max(abs(v) for v in values)
output = array.array("h", (round(v * gain * 32767) for v in values))
if sys.byteorder != "little":
    output.byteswap()
with wave.open(str(ROOT / "SwipeTennis/hit.wav"), "wb") as target:
    target.setparams((1, 2, rate, len(output), "NONE", "not compressed"))
    target.writeframes(output.tobytes())
print("Prepared 200 ms recorded tennis forehand, mono PCM, peak −1.94 dBFS")
