.PHONY: all setup build run test stop clean

all: build

setup:
	@./scripts/setup_mac.sh

build:
	@./scripts/build_app.sh

run:
	@./scripts/run.sh

test:
	@./scripts/test.sh

stop:
	@pkill -f "Press To Write.app/Contents/MacOS/PressToWrite" 2>/dev/null || true
	@pkill -f "Metatron.app/Contents/MacOS/Metatron" 2>/dev/null || true
	@pkill -f "whisper_daemon.py" 2>/dev/null || true
	@rm -f /tmp/presstowrite.sock /tmp/metatron.sock 2>/dev/null || true
	@echo "Press To Write stopped."

clean: stop
	@rm -rf .build "Press To Write.app" Metatron.app /tmp/presstowrite* /tmp/metatron*
	@echo "Cleaned."
