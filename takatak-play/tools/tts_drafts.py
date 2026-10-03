#!/usr/bin/env python3
"""Draft voice lines so games can be built and timed before studio recording.

  --engine espeak  (default; works on the Pi, robotic but instant)
  --engine parler  (PC with GPU: AI4Bharat Indic Parler-TTS for mr/hi, also en)
                   pip install git+https://github.com/huggingface/parler-tts.git soundfile

Writes content/voice/drafts/<lang>/<line_id>_v<variant>.wav. voice_pipeline.py
then processes them and marks them "draft": true so they are never shipped.
Lines that already have a studio recording in voice/raw/ are skipped.
"""
import argparse
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from content_common import LANGS, VOICE, read_lines  # noqa: E402

ESPEAK_VOICES = {"mr": "mr", "hi": "hi", "en": "en"}
PARLER_DESC = {
    "mr": "Sunita speaks in a warm, happy, slightly animated voice at a slow pace, very clear audio, close-sounding recording.",
    "hi": "Divya speaks in a warm, happy, slightly animated voice at a slow pace, very clear audio, close-sounding recording.",
    "en": "Mary speaks in a warm, happy, slightly animated voice at a slow pace, very clear audio, close-sounding recording.",
}


def studio_file(line_id, variant, lang):
    return os.path.join(VOICE, "raw", f"{line_id}_v{variant}_{lang}.wav")


class Espeak:
    def __init__(self, speed):
        if shutil.which("espeak-ng") is None:
            sys.exit("espeak-ng not found: sudo apt install espeak-ng")
        self.speed = speed

    def synth(self, text, lang, out):
        subprocess.run(["espeak-ng", "-v", ESPEAK_VOICES[lang], "-s", str(self.speed), "-w", out, text],
                       check=True)


class Parler:
    def __init__(self):
        import soundfile  # noqa: F401
        import torch
        from parler_tts import ParlerTTSForConditionalGeneration
        from transformers import AutoTokenizer
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        name = "ai4bharat/indic-parler-tts"
        self.model = ParlerTTSForConditionalGeneration.from_pretrained(name).to(self.device)
        self.tok = AutoTokenizer.from_pretrained(name)
        self.desc_tok = AutoTokenizer.from_pretrained(self.model.config.text_encoder._name_or_path)

    def synth(self, text, lang, out):
        import soundfile as sf
        d = self.desc_tok(PARLER_DESC[lang], return_tensors="pt").to(self.device)
        p = self.tok(text, return_tensors="pt").to(self.device)
        gen = self.model.generate(input_ids=d.input_ids, attention_mask=d.attention_mask,
                                  prompt_input_ids=p.input_ids, prompt_attention_mask=p.attention_mask)
        sf.write(out, gen.cpu().numpy().squeeze(), self.model.config.sampling_rate)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", choices=["espeak", "parler"], default="espeak")
    ap.add_argument("--speed", type=int, default=130, help="espeak words per minute")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--only", help="comma-separated line_ids")
    args = ap.parse_args()
    engine = Parler() if args.engine == "parler" else Espeak(args.speed)
    only = set(args.only.split(",")) if args.only else None
    made = skipped = 0
    for lid, e in read_lines().items():
        if only and lid not in only:
            continue
        for v, data in e["variants"].items():
            for lang in LANGS:
                out = os.path.join(VOICE, "drafts", lang, f"{lid}_v{v}.wav")
                if os.path.exists(studio_file(lid, v, lang)) or (os.path.exists(out) and not args.force):
                    skipped += 1
                    continue
                os.makedirs(os.path.dirname(out), exist_ok=True)
                engine.synth(data["text"][lang], lang, out)
                made += 1
    print(f"tts drafts ({args.engine}): {made} made, {skipped} skipped")


if __name__ == "__main__":
    main()
