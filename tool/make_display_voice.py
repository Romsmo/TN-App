"""Makes the 18 German voice clips for the TN display (WAV, 16 kHz, mono, 16 bit) with Piper and the Thorsten voice.

    python tool/make_display_voice.py --piper PATH/piper.exe --model PATH/de_DE-thorsten-medium.onnx

Sources (checked 2026-10-25): Piper 2023.11.14-2 (MIT, github.com/rhasspy/piper); the voice `de_DE-thorsten-medium` from
huggingface.co/rhasspy/piper-voices, trained on the Thorsten-Voice data set (CC0). The clips are written to
assets/display_audio/audio/voice/de/. Only the standard library is needed (resampling with `audioop`, Python up to 3.12).
The generated files are committed; the voice model and Piper are not.
"""
import argparse
import audioop
import subprocess
import sys
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "display_audio" / "audio" / "voice" / "de"

# file stem -> spoken text (the stems are the display's clip names, docs/audio-assets.md of the display project)
PHRASES = {
    "achtung": "Achtung.",
    "in": "in",
    "blitzer_fest": "fester Blitzer",
    "blitzer_mobil": "mobiler Blitzer",
    "blitzer_anhaenger": "Blitzeranhänger",
    "blitzer_rotlicht": "Rotlichtblitzer",
    "blitzer_abstand": "Abstandsmessung",
    "gefahr_stau": "Stau",
    "gefahr_glaette": "Glätte",
    "gefahr_unfall": "Unfall",
    "gefahr_baustelle": "Baustelle",
    "gefahr_panne": "Panne",
    "gefahr_hindernis": "Hindernis auf der Fahrbahn",
    "d_100": "einhundert Metern",
    "d_200": "zweihundert Metern",
    "d_300": "dreihundert Metern",
    "d_500": "fünfhundert Metern",
    "d_800": "achthundert Metern",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--piper", required=True, type=Path)
    ap.add_argument("--model", required=True, type=Path)
    ap.add_argument("--work", type=Path, default=ROOT / "build" / "voice-raw")
    args = ap.parse_args()
    args.work.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    for stem, text in PHRASES.items():
        raw = args.work / f"{stem}.wav"
        r = subprocess.run(
            [str(args.piper), "--model", str(args.model), "--output_file", str(raw)],
            input=text.encode("utf-8"),
            capture_output=True,
            cwd=str(args.piper.parent),
        )
        if r.returncode != 0 or not raw.exists():
            sys.exit(f"piper failed for {stem}: {r.stderr.decode('utf-8', 'replace')[-400:]}")
        with wave.open(str(raw), "rb") as w:
            ch, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.readframes(w.getnframes())
        if ch != 1:
            frames = audioop.tomono(frames, width, 0.5, 0.5)
        if width != 2:
            frames = audioop.lin2lin(frames, width, 2)
        frames, _ = audioop.ratecv(frames, 2, 1, rate, 16000, None)
        peak = audioop.max(frames, 2) or 1
        frames = audioop.mul(frames, 2, min(3.0, 0.8 * 32767 / peak))  # about equal loudness, no clipping
        frames = b"\x00\x00" * 800 + frames + b"\x00\x00" * 1600  # 50 ms before, 100 ms after
        with wave.open(str(OUT / f"{stem}.wav"), "wb") as o:
            o.setnchannels(1)
            o.setsampwidth(2)
            o.setframerate(16000)
            o.writeframes(frames)
        print(f"{stem}: {len(frames) / 32000:.2f} s")


if __name__ == "__main__":
    main()
