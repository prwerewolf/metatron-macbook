.PHONY: all setup setup-fast build run test privacy install-hooks stop clean

all: build

setup:
	@./scripts/setup_mac.sh

setup-fast:
	@python3 -B scripts/setup_fast.py

build:
	@./scripts/build_app.sh

run:
	@./scripts/run.sh

test:
	@./scripts/test.sh

privacy:
	@python3 -B scripts/privacy_check.py

install-hooks:
	@./scripts/install_hooks.sh

stop:
	@pkill -f "Press To Write.app/Contents/MacOS/PressToWrite" 2>/dev/null || true
	@pkill -f "Metatron.app/Contents/MacOS/Metatron" 2>/dev/null || true
	@pkill -f "whisper_daemon.py" 2>/dev/null || true
	@rm -f /tmp/presstowrite.sock /tmp/metatron.sock 2>/dev/null || true
	@echo "Press To Write stopped."

clean: stop
	@rm -rf .build "Press To Write.app" Metatron.app /tmp/presstowrite* /tmp/metatron*
	@echo "Cleaned."
