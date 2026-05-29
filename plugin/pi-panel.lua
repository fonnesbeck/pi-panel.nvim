-- Auto-loaded on startup: register the :Pi* commands so they exist even before
-- (or without) an explicit require("pi-panel").setup(). Registration is
-- idempotent and lazy — it pulls in nothing heavy until a command runs.

if vim.g.loaded_pi_panel then
  return
end
vim.g.loaded_pi_panel = true

require("pi-panel.commands").register()
