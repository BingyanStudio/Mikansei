#!/usr/bin/env python3
"""Create original, short PCM reminder tones (no Apple Clock assets)."""
from pathlib import Path
import math
import struct
import wave

target = Path(__file__).resolve().parents[1] / "App" / "Resources"
target.mkdir(exist_ok=True)
rate = 22050
tones = {
    "morning": [(0, 523.25), (0.6, 659.25), (1.2, 783.99), (2, 1046.5)],
    "chime": [(0, 880), (0.35, 1174.66), (1.4, 880), (1.75, 1174.66)],
    "pulse": [(i * 0.45, 660 if i % 2 == 0 else 880) for i in range(7)],
}
for name, notes in tones.items():
    with wave.open(str(target / f"mikansei-{name}.wav"), "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(rate)
        frames = []
        for index in range(rate * 4):
            time = index / rate
            value = 0
            for onset, frequency in notes:
                age = time - onset
                if 0 <= age < 1.25:
                    envelope = min(1, age / 0.015) * math.exp(-4 * age) * min(1, (1.25 - age) / 0.06)
                    value += envelope * (math.sin(2 * math.pi * frequency * age) + 0.2 * math.sin(2 * math.pi * frequency * 2 * age))
            frames.append(struct.pack("<h", int(max(-1, min(1, value * 0.38)) * 32767)))
        sound.writeframes(b"".join(frames))
