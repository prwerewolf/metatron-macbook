#!/usr/bin/env python3
"""
Metatron Local Audio Daemon
High-speed resident speech-to-text service leveraging Apple Silicon M4 Max GPU/Metal via mlx-whisper.
Listens on Unix domain socket: /tmp/metatron.sock
"""

import os
import sys
import json
import time
import socket
import signal
import threading
import traceback

SOCKET_PATH = "/tmp/metatron.sock"
DEFAULT_MODEL = "mlx-community/whisper-large-v3-turbo"
FALLBACK_MODEL = "mlx-community/whisper-base.en"

active_model = DEFAULT_MODEL
mlx_whisper = None
is_engine_ready = False
engine_load_error = None
engine_lock = threading.Lock()

def load_engine_background():
    global mlx_whisper, is_engine_ready, engine_load_error
    try:
        print("[Metatron Daemon] Loading MLX Whisper engine onto Metal GPU in background...")
        import mlx_whisper as mw
        with engine_lock:
            mlx_whisper = mw
            is_engine_ready = True
        print("[Metatron Daemon] MLX Whisper engine ready for high-speed inference.")
    except Exception as e:
        with engine_lock:
            engine_load_error = str(e)
        print(f"[Metatron Daemon] Failed to load mlx_whisper: {e}", file=sys.stderr)

def transcribe_file(audio_path: str) -> dict:
    global mlx_whisper, active_model, is_engine_ready, engine_load_error

    # Wait up to 30s for engine if still warming up
    waited = 0
    while not is_engine_ready and engine_load_error is None and waited < 30:
        time.sleep(0.5)
        waited += 0.5

    if engine_load_error:
        return {"error": f"MLX engine failed to load: {engine_load_error}"}

    if not is_engine_ready or not mlx_whisper:
        return {"error": "MLX engine timed out during initial warm-up"}

    if not os.path.exists(audio_path):
        return {"error": f"Audio file not found: {audio_path}"}

    start_time = time.time()
    try:
        result = mlx_whisper.transcribe(
            audio_path,
            path_or_hf_repo=active_model,
            fp16=True,
            verbose=False
        )
        duration = round(time.time() - start_time, 3)
        text = result.get("text", "").strip()

        # Ephemeral Privacy Policy: Delete the audio file immediately after transcription!
        try:
            if os.path.exists(audio_path):
                os.remove(audio_path)
        except Exception:
            pass

        return {
            "success": True,
            "text": text,
            "duration": duration,
            "model": active_model
        }
    except Exception as e:
        print(f"[Metatron Daemon] Primary model failed, trying fallback: {e}")
        try:
            result = mlx_whisper.transcribe(
                audio_path,
                path_or_hf_repo=FALLBACK_MODEL,
                fp16=True,
                verbose=False
            )
            duration = round(time.time() - start_time, 3)
            text = result.get("text", "").strip()

            if os.path.exists(audio_path):
                os.remove(audio_path)

            return {
                "success": True,
                "text": text,
                "duration": duration,
                "model": FALLBACK_MODEL
            }
        except Exception as err:
            return {"error": str(err), "trace": traceback.format_exc()}

def cleanup():
    if os.path.exists(SOCKET_PATH):
        try:
            os.unlink(SOCKET_PATH)
        except OSError:
            pass

def run_server():
    cleanup()
    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))
    signal.signal(signal.SIGTERM, lambda s, f: sys.exit(0))

    # 1. Bind socket immediately so clients can connect with zero delay
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET_PATH)
    server.listen(5)
    os.chmod(SOCKET_PATH, 0o777)
    print(f"[Metatron Daemon] Socket initialized at {SOCKET_PATH}")

    # 2. Warm up MLX on background thread
    warmup_thread = threading.Thread(target=load_engine_background, daemon=True)
    warmup_thread.start()

    try:
        while True:
            conn, _ = server.accept()
            try:
                data = b""
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    data += chunk
                    if b"\n" in data:
                        break

                if not data:
                    conn.close()
                    continue

                line = data.decode("utf-8").strip()
                if not line:
                    conn.close()
                    continue

                req = json.loads(line)
                action = req.get("action", "")

                if action == "ping":
                    res = {
                        "success": True,
                        "status": "ready" if is_engine_ready else "warming_up",
                        "time": time.time()
                    }
                elif action == "transcribe":
                    audio_path = req.get("path", "")
                    res = transcribe_file(audio_path)
                elif action == "set_model":
                    global active_model
                    active_model = req.get("model", DEFAULT_MODEL)
                    res = {"success": True, "model": active_model}
                else:
                    res = {"error": f"Unknown action: {action}"}

                response_bytes = (json.dumps(res) + "\n").encode("utf-8")
                conn.sendall(response_bytes)
            except Exception as e:
                err_resp = (json.dumps({"error": str(e)}) + "\n").encode("utf-8")
                conn.sendall(err_resp)
            finally:
                conn.close()
    finally:
        server.close()
        cleanup()

if __name__ == "__main__":
    run_server()
