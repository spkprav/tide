# Tide — native macOS terminal
# Common targets: build, install, run, clean

APP            := Tide.app
PREFIX         ?= /Applications
INSTALL_PATH   := $(PREFIX)/$(APP)
CONFIG         ?= release

.PHONY: all build debug release install uninstall run open clean reset help

all: build

help:
	@echo "Tide build targets:"
	@echo "  make build       Build release .app (default)"
	@echo "  make debug       Build debug .app"
	@echo "  make install     Build + copy to $(PREFIX)"
	@echo "  make uninstall   Remove installed .app from $(PREFIX)"
	@echo "  make run         Build + launch .app"
	@echo "  make open        Launch already-built .app"
	@echo "  make clean       Remove build artifacts"
	@echo "  make reset       clean + wipe SwiftPM caches"

build release:
	CONFIG=release ./build.sh

debug:
	CONFIG=debug ./build.sh

$(APP):
	$(MAKE) build

install: $(APP)
	@echo "==> Installing to $(INSTALL_PATH)"
	@if [ -d "$(INSTALL_PATH)" ]; then \
		echo "==> Removing existing $(INSTALL_PATH)"; \
		rm -rf "$(INSTALL_PATH)"; \
	fi
	cp -R "$(APP)" "$(INSTALL_PATH)"
	@# Clear quarantine attr so Gatekeeper does not block first launch
	-xattr -dr com.apple.quarantine "$(INSTALL_PATH)" 2>/dev/null || true
	@echo "==> Installed. Launch: open '$(INSTALL_PATH)'"

uninstall:
	@if [ -d "$(INSTALL_PATH)" ]; then \
		echo "==> Removing $(INSTALL_PATH)"; \
		rm -rf "$(INSTALL_PATH)"; \
	else \
		echo "==> Not installed at $(INSTALL_PATH)"; \
	fi

run: build open

open:
	open "$(APP)"

clean:
	rm -rf .build "$(APP)"

reset: clean
	rm -rf .swiftpm Package.resolved
