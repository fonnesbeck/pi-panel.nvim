EXT_DIR := extensions/pi-nvim-bridge

.PHONY: deps build typecheck test lint format audit clean

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

# Test suites: Lua (zero-dependency runner under tests/) + extension (node:test).
test:
	nvim --headless -l tests/run.lua
	cd $(EXT_DIR) && npm test

lint:
	@command -v stylua >/dev/null 2>&1 && stylua --check lua/ tests/ \
		|| echo "stylua not installed; skipping Lua lint"
	@if ls $(EXT_DIR)/eslint.config.* $(EXT_DIR)/.eslintrc* >/dev/null 2>&1; then \
		cd $(EXT_DIR) && npx --no-install eslint . ; \
	else echo "eslint not configured; skipping TypeScript lint"; fi

# Scan the extension's dependencies for known vulnerabilities (also run in CI).
audit:
	cd $(EXT_DIR) && npm audit --audit-level=moderate

format:
	@command -v stylua >/dev/null 2>&1 && stylua lua/ tests/ \
		|| echo "stylua not installed; skipping Lua format"

clean:
	rm -rf $(EXT_DIR)/dist $(EXT_DIR)/node_modules
