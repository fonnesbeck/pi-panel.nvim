EXT_DIR := extensions/pi-nvim-bridge

.PHONY: deps build typecheck test lint format clean

# Install the extension's npm deps (contributor-side; end users get the
# committed dist/index.js bundle).
deps:
	cd $(EXT_DIR) && npm install

# Bundle the extension + its third-party deps (ws) into the committed
# dist/index.js. Pi-provided packages stay external (see package.json).
build:
	cd $(EXT_DIR) && npm run build

typecheck:
	cd $(EXT_DIR) && npm run typecheck

# Lua test suite (zero-dependency runner under tests/).
test:
	nvim --headless -l tests/run.lua

lint:
	@command -v stylua >/dev/null 2>&1 && stylua --check lua/ tests/ \
		|| echo "stylua not installed; skipping Lua lint"

format:
	@command -v stylua >/dev/null 2>&1 && stylua lua/ tests/ \
		|| echo "stylua not installed; skipping Lua format"

clean:
	rm -rf $(EXT_DIR)/dist $(EXT_DIR)/node_modules
