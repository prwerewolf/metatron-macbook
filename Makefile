.PHONY: all build run test stop clean

all: build

build:
	@./scripts/build_app.sh

run:
	@./scripts/run.sh

test:
	@swiftc -parse-as-library Sources/Metatron/Engine/TextCleaner.swift tests/test_cleaner.swift -o /tmp/metatron_test && /tmp/metatron_test

stop:
	@pkill -f "Metatron.app/Contents/MacOS/Metatron" 2>/dev/null || true
	@pkill -f "whisper_daemon.py" 2>/dev/null || true
	@rm -f /tmp/metatron.sock 2>/dev/null || true
	@echo "Metatron stopped."

clean: stop
	@rm -rf .build Metatron.app /tmp/metatron*
	@echo "Cleaned."
