"""Render the legacy original CAS score from notes and synthesized instruments.

Build-time only. Requires NumPy and FFmpeg with libopus (imageio-ffmpeg is an
optional source of the binary). No samples or external recording are read.

The shipped score/ directory now contains the ledgered World of Warships OST
cuts (score/ledger.json). Running this script would overwrite them, so it
refuses unless --force-synthetic is passed. The old synthetic files are kept in
artifacts/client/audio-archive/old-score/.
"""
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np


RATE = 24_000
OUT = Path(__file__).with_name("score")

# D minor is the common tonal center. The prologue answers a rising fifth with
# a falling third. The same intervals are compressed and repeated at contact.
PROLOGUE = [(50, 57, 60, 64, 65), (46, 53, 57, 62, 65), (53, 57, 60, 64, 67), (48, 55, 60, 62, 67),
            (43, 50, 55, 58, 62), (46, 53, 57, 62, 65), (45, 52, 55, 60, 64), (50, 57, 60, 64, 65)]
MANEUVER = [(38, 50, 57, 65), (34, 50, 53, 62), (43, 50, 58, 62), (33, 45, 52, 60)] * 2
ENGAGEMENT = [(38, 50, 57, 65), (46, 50, 53, 62), (41, 48, 57, 60), (36, 48, 55, 64),
              (38, 50, 57, 65), (43, 50, 55, 62), (34, 46, 53, 62), (45, 52, 57, 64)] * 2
MOTIF = ((0, 62, 1.35), (1.5, 69, .92), (2.5, 72, 1.25), (4, 65, 1.8), (6, 64, 1.8),
         (8, 62, 1.35), (9.5, 69, .9), (10.5, 67, 1.2), (12, 65, 1.7), (14, 57, 1.4))


class Score:
    def __init__(self, bpm, bars, *, loop=True):
        self.beat = 60 / bpm
        self.loop = loop
        self.samples = np.zeros((round(bars * 4 * self.beat * RATE), 2))
        self.noise = np.random.default_rng(28)

    def add(self, at, signal, pan, volume):
        start = round(at * self.beat * RATE)
        gain = volume * np.sqrt([(1 - pan) / 2, (1 + pan) / 2])
        length = min(len(signal), len(self.samples) - start)
        self.samples[start:start + length] += signal[:length, None] * gain
        if self.loop and length < len(signal):
            self.samples[:len(signal) - length] += signal[length:, None] * gain

    def note(self, at, note, duration, voice, volume, pan=0):
        t = np.arange(round(duration * self.beat * RATE)) / RATE
        angle = 2 * np.pi * 440 * 2 ** ((note - 69) / 12) * t
        if voice == "felt":
            signal = (np.sin(angle) + .34 * np.sin(2 * angle) + .12 * np.sin(3 * angle)) * np.exp(-2.4 * t)
            attack, release = .012, .13
        elif voice == "bow":
            signal = (.8 * np.sin(angle) + .27 * np.sin(angle * 1.002) + .19 * np.sin(2 * angle)
                      + .13 * np.sin(3 * angle + .14 * np.sin(2 * np.pi * 4.2 * t)))
            attack, release = .28, .4
        else:  # Soft brass, with enough upper harmonics for small phone speakers.
            swell = 1 - np.exp(-7 * t)
            signal = np.sin(angle) + swell * (.32 * np.sin(2 * angle) + .22 * np.sin(3 * angle))
            attack, release = .11, .23
        envelope = np.minimum(1, t / attack) * np.minimum(1, (t[-1] - t) / release)
        self.add(at, signal * envelope, pan, volume)

    def drum(self, at, kind, volume, pan=0):
        t = np.arange(RATE // 2) / RATE
        noise = self.noise.uniform(-1, 1, len(t))
        if kind == "low":
            sweep = 48 * t + 2.6 * (1 - np.exp(-34 * t))
            signal = np.sin(2 * np.pi * sweep) * np.exp(-12 * t) + .13 * noise * np.exp(-32 * t)
        else:
            signal = (.7 * noise + .25 * np.sin(2 * np.pi * 176 * t)) * np.exp(-31 * t)
        self.add(at, signal * np.minimum(1, t / .004), pan, volume)

    def export(self, encoder, file):
        # A small early reflection sets depth without using an impulse response.
        direct = self.samples.copy()
        for ms, level in ((73, .17), (127, .09), (201, .04)):
            reflected = np.roll(direct[:, ::-1], ms * RATE // 1000, axis=0)
            if not self.loop:
                reflected[:ms * RATE // 1000] = 0
            self.samples += level * reflected
        if not self.loop:
            fade = min(RATE, len(self.samples))
            self.samples[-fade:] *= np.linspace(1, 0, fade)[:, None]
        # Scale to a shared target but preserve the engagement cue's punch.
        rms = np.sqrt(np.mean(self.samples ** 2))
        self.samples *= min(.115 / rms, .79 / np.max(np.abs(self.samples)))
        pcm = np.rint(self.samples * 32767).astype("<i2").tobytes()
        subprocess.run([encoder, "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "2",
                        "-i", "pipe:0", "-map_metadata", "-1", "-fflags", "+bitexact", "-c:a", "libopus", "-b:a", "36k",
                        "-vbr", "constrained", str(file)],
                       input=pcm, check=True)


def prologue():
    music = Score(84, 8)
    for index, chord in enumerate(PROLOGUE):
        at = index * 4
        music.note(at, chord[0] - 12, 3.8, "bow", .19, -.18)
        for voice, pitch in enumerate(chord[1:]):
            music.note(at, pitch, 3.9, "bow", .07, -.55 + .35 * voice)
        for step, voice in enumerate((1, 2, 3, 2, 4, 3, 2, 1)):
            music.note(at + step / 2, chord[voice], .85, "felt", .085, (-1) ** step * .4)
    for at, pitch, length in MOTIF:
        for offset in (0, 16):
            music.note(at + offset, pitch + (12 if offset and at in (2.5, 10.5) else 0), length,
                       "felt", .21, .12)
    return music


def maneuver():
    music = Score(80, 8)
    for index, chord in enumerate(MANEUVER):
        at = index * 4
        for voice, pitch in enumerate(chord):
            music.note(at, pitch, 3.95, "bow", (.24, .13, .08, .05)[voice], -.4 + .28 * voice)
        for beat, pitch in ((.25, chord[0] + 12), (1.75, chord[1]), (2.5, chord[2]), (3.25, chord[1])):
            music.note(at + beat, pitch, .62, "felt", .105, .35)
        if index in (1, 3, 5, 7):
            music.note(at + .45, (62, 69, 65, 64)[index // 2], 2.1, "brass", .115, -.21)
    return music


def engagement():
    music = Score(108, 16)
    for index, chord in enumerate(ENGAGEMENT):
        at = index * 4
        for voice, pitch in enumerate(chord[1:]):
            music.note(at, pitch, 3.92, "bow", .09, -.42 + .42 * voice)
        for beat, pitch in ((0, chord[0]), (.75, chord[0] + 12), (1.5, chord[2]), (2, chord[0]),
                            (2.75, chord[0] + 12), (3.5, chord[1])):
            music.note(at + beat, pitch, .47, "felt", .23, -.18)
        for beat in (0, 1.5, 2.75):
            music.drum(at + beat, "low", .27)
        for beat in (1, 3):
            music.drum(at + beat, "rim", .14, .28)
        phrase = {0: ((0, 62, 1.25), (1.5, 69, .9), (2.5, 72, 1.35)),
                  1: ((0, 65, 1.65), (2, 64, 1.65))}.get(index % 4, ())
        for beat, pitch, length in phrase:
            music.note(at + beat, pitch, length, "brass", .22, .13)
    return music


def ending(won):
    music = Score(84 if won else 72, 4, loop=False)
    chords = [(50, 57, 62, 66), (47, 54, 59, 62), (43, 50, 55, 62), (50, 57, 62, 66)] if won else PROLOGUE[-4:]
    for index, chord in enumerate(chords):
        for voice, pitch in enumerate(chord):
            music.note(index * 4, pitch, 3.96, "bow", .13 if voice else .23, -.5 + voice * .24)
    notes = ((0, 62, 1), (1, 69, 1), (2, 74, 1.9), (4, 71, 3), (8, 69, 2), (10, 66, 1.8), (12, 62, 3.9)) if won else (
             (0, 69, 1.8), (2.5, 65, 1.2), (5, 64, 2), (8, 60, 1.85), (12, 62, 3.9))
    for at, pitch, duration in notes:
        music.note(at, pitch, duration, "brass" if won else "felt", .25, .13)
    return music


def main():
    if "--force-synthetic" not in sys.argv:
        raise SystemExit("score/ holds the ledgered World of Warships OST cuts; pass --force-synthetic to overwrite them with the legacy synthetic render")
    ffmpeg = shutil.which("ffmpeg")
    if not ffmpeg:
        from imageio_ffmpeg import get_ffmpeg_exe
        ffmpeg = get_ffmpeg_exe()
    OUT.mkdir(exist_ok=True)
    for name, cue in (("prologue", prologue), ("maneuver", maneuver), ("engagement", engagement),
                      ("victory", lambda: ending(True)), ("defeat", lambda: ending(False))):
        cue().export(ffmpeg, OUT / f"{name}.ogg")


if __name__ == "__main__":
    main()
