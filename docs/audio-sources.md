# Where the display sounds come from

| What | Source | Licence | Checked |
|---|---|---|---|
| Five event tones (`assets/display_audio/audio/tones/`) | the display project `Romsmo/TN-DSP`, `tools/audio/tones/` (synthesised by its own `gen_audio_tones.py`) | MIT, original work of the same owner | 2026-10-25 |
| 18 German voice clips (`assets/display_audio/audio/voice/de/`) | made on 2026-10-25 with `tool/make_display_voice.py`: **Piper** 2023.11.14-2 (`piper_windows_amd64.zip`, 22,477,236 bytes, github.com/rhasspy/piper, MIT; the repository was archived by its owner on 2025-10-06) and the voice **`de_DE-thorsten-medium`** (`.onnx`, 63,201,294 bytes, SHA-256 `7e64762d…7819`, matches the value Hugging Face publishes; huggingface.co/rhasspy/piper-voices) | the voice is trained on the **Thorsten-Voice** data set, **CC0** (the model card on Hugging Face says so and lists MIT for the model card itself) | 2026-10-25 |

Notes:

* Piper uses the espeak-ng phonemizer (GPL-3). Only Piper's **output audio** is shipped, not the program or its libraries; the generated
  speech is not a derivative of the phonemizer. Piper and the voice model are **not** in this repository (they were only used to
  generate the clips).
* The clips are 16 kHz mono 16-bit WAV as the display needs (a little silence at the start and end, equal peak level). They are a
  synthetic voice; they have not been listened to on the display yet. To use other recordings, keep the file names and the format.
* The Windows voice (*Microsoft Hedda*) that the display project's own tool uses is **not** used here: whether its output may be
  redistributed is unclear (the display project says so).
