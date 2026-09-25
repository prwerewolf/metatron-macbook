#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/metatron-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
MODULE_CACHE="${CLANG_MODULE_CACHE_PATH:-$TEST_DIR/module-cache}"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/Engine/TextCleaner.swift tests/test_cleaner.swift \
    -o "$TEST_DIR/cleaner"
"$TEST_DIR/cleaner"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/Engine/SpeechEngine.swift Sources/Metatron/Engine/TextCleaner.swift \
    Sources/Metatron/Engine/LocalDaemonClient.swift tests/test_local_daemon_client.swift \
    -o "$TEST_DIR/local-daemon-client"
"$TEST_DIR/local-daemon-client"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/Core/HotkeyManager.swift tests/test_hotkeys.swift \
    -o "$TEST_DIR/hotkeys"
"$TEST_DIR/hotkeys"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/Core/InsertionTarget.swift Sources/Metatron/Core/TextInserter.swift \
    tests/test_insertion_target.swift \
    -o "$TEST_DIR/insertion-target"
"$TEST_DIR/insertion-target"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/Core/AudioInputDevice.swift tests/test_microphone.swift \
    -o "$TEST_DIR/microphone"
"$TEST_DIR/microphone"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/Core/AudioInputDevice.swift Sources/Metatron/Core/AudioInputDeviceController.swift \
    Sources/Metatron/Core/AudioRecorder.swift tests/test_audio_conversion.swift \
    -o "$TEST_DIR/audio-conversion"
"$TEST_DIR/audio-conversion"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/UI/FloatingPill/PillDisplayRestoration.swift tests/test_pill_display.swift \
    -o "$TEST_DIR/pill-display"
"$TEST_DIR/pill-display"

swiftc -module-cache-path "$MODULE_CACHE" -parse-as-library \
    Sources/Metatron/Core/RescueAudioController.swift \
    Sources/Metatron/App/AppState.swift Sources/Metatron/Engine/TextCleaner.swift \
    Sources/Metatron/Engine/SpeechEngine.swift tests/test_app_state.swift \
    -o "$TEST_DIR/app-state"
"$TEST_DIR/app-state"

python3 -B -m unittest discover -s tests -p 'test_*.py'
