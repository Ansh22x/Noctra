"""
Noctra WhisperX Forced-Alignment Sidecar Server
================================================
Synchronizes Genius (or plain-text) lyrics against audio using WhisperX
phoneme/wav2vec2 forced alignment, or transcribes + aligns audio directly.

Install dependencies:
  pip install whisperx fastapi uvicorn requests

Run:
  python tool/whisperx_server.py --port 8765 --model base --device cpu
"""

from __future__ import annotations

import argparse
import os
import tempfile
from typing import Any, Dict, List, Optional

import requests
import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Noctra WhisperX Sync Server", version="1.0.0")

_MODEL_CACHE: Dict[str, Any] = {}
_ALIGN_CACHE: Dict[str, Any] = {}
_CONFIG = {"model": "base", "device": "cpu", "compute_type": "int8"}


class AlignRequest(BaseModel):
    title: Optional[str] = None
    artist: Optional[str] = None
    duration_sec: Optional[int] = None
    audio_path: Optional[str] = None
    audio_url: Optional[str] = None
    lyrics: Optional[str] = None
    language: Optional[str] = None


def _get_whisper_model():
    import whisperx

    key = f"{_CONFIG['model']}:{_CONFIG['device']}:{_CONFIG['compute_type']}"
    if key not in _MODEL_CACHE:
        _MODEL_CACHE[key] = whisperx.load_model(
            _CONFIG["model"],
            _CONFIG["device"],
            compute_type=_CONFIG["compute_type"],
        )
    return _MODEL_CACHE[key]


def _get_align_model(language_code: str):
    import whisperx

    if language_code not in _ALIGN_CACHE:
        model_a, metadata = whisperx.load_align_model(
            language_code=language_code,
            device=_CONFIG["device"],
        )
        _ALIGN_CACHE[language_code] = (model_a, metadata)
    return _ALIGN_CACHE[language_code]


def _format_lrc_timestamp(seconds: float) -> str:
    ms_total = max(0, int(round(seconds * 1000)))
    minutes = ms_total // 60000
    rem_ms = ms_total % 60000
    secs = rem_ms // 1000
    hundredths = (rem_ms % 1000) // 10
    return f"[{minutes:02d}:{secs:02d}.{hundredths:02d}]"


def _resolve_audio_file(req: AlignRequest, tmp_dir: str) -> str:
    if req.audio_path and os.path.isfile(req.audio_path):
        return req.audio_path
    if req.audio_url:
        resp = requests.get(req.audio_url, stream=True, timeout=30)
        resp.raise_for_status()
        out_path = os.path.join(tmp_dir, "audio_input.mp3")
        with open(out_path, "wb") as f:
            for chunk in resp.iter_content(chunk_size=65536):
                if chunk:
                    f.write(chunk)
        return out_path
    raise HTTPException(status_code=400, detail="Missing valid audio_path or audio_url")


@app.get("/health")
def health():
    return {"status": "ok", "engine": "whisperx", **_CONFIG}


@app.post("/align")
def align_lyrics(req: AlignRequest):
    import whisperx

    with tempfile.TemporaryDirectory(prefix="noctra_wx_") as tmp_dir:
        audio_file = _resolve_audio_file(req, tmp_dir)
        audio = whisperx.load_audio(audio_file)
        audio_duration = len(audio) / 16000.0

        model = _get_whisper_model()
        transcribed = model.transcribe(audio, batch_size=8, language=req.language)
        lang = req.language or transcribed.get("language") or "en"

        model_a, metadata = _get_align_model(lang)

        # If Genius plain lyrics are provided, build evenly spaced seed segments
        # and let WhisperX's wav2vec2 forced aligner snap them to exact audio.
        forced_aligned = False
        if req.lyrics and req.lyrics.strip():
            raw_lines = [
                ln.strip()
                for ln in req.lyrics.splitlines()
                if ln.strip() and not (ln.strip().startswith("[") and ln.strip().endswith("]"))
            ]
            if raw_lines:
                step = max(audio_duration / len(raw_lines), 0.5)
                seed_segments = [
                    {
                        "text": line,
                        "start": round(i * step, 3),
                        "end": round(min((i + 1) * step, audio_duration), 3),
                    }
                    for i, line in enumerate(raw_lines)
                ]
                try:
                    aligned = whisperx.align(
                        seed_segments,
                        model_a,
                        metadata,
                        audio,
                        _CONFIG["device"],
                        return_char_alignments=False,
                    )
                    forced_aligned = True
                except Exception:
                    # Fall back to aligning Whisper's own transcript segments
                    aligned = whisperx.align(
                        transcribed["segments"],
                        model_a,
                        metadata,
                        audio,
                        _CONFIG["device"],
                        return_char_alignments=False,
                    )
            else:
                aligned = whisperx.align(
                    transcribed["segments"],
                    model_a,
                    metadata,
                    audio,
                    _CONFIG["device"],
                    return_char_alignments=False,
                )
        else:
            aligned = whisperx.align(
                transcribed["segments"],
                model_a,
                metadata,
                audio,
                _CONFIG["device"],
                return_char_alignments=False,
            )

        lines: List[Dict[str, Any]] = []
        lrc_rows: List[str] = []
        for seg in aligned.get("segments", []):
            text = (seg.get("text") or "").strip()
            start = seg.get("start")
            end = seg.get("end")
            if not text or start is None:
                continue
            lines.append(
                {
                    "start": float(start),
                    "end": float(end if end is not None else start + 2.0),
                    "text": text,
                }
            )
            lrc_rows.append(f"{_format_lrc_timestamp(float(start))}{text}")

        return {
            "language": lang,
            "forced_aligned": forced_aligned,
            "lines": lines,
            "synced_lrc": "\n".join(lrc_rows),
        }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Noctra WhisperX Sync Server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--model", default="base")
    parser.add_argument("--device", default="cpu")
    parser.add_argument("--compute-type", default="int8")
    args = parser.parse_args()

    _CONFIG["model"] = args.model
    _CONFIG["device"] = args.device
    _CONFIG["compute_type"] = args.compute_type

    uvicorn.run(app, host=args.host, port=args.port)
