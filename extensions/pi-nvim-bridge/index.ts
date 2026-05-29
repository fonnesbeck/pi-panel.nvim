// pi-nvim-bridge — Phase 2 stub.
//
// The real extension (a persistent WebSocket client plus the Neovim tool
// delegations — nvim_open_file, nvim_open_diff, …) lands in Phase 3. For now
// this stub proves the launch path end-to-end: pi-panel.nvim starts pi with
//   pi -e <abs>/extensions/pi-nvim-bridge/dist/index.js
// and injects PI_IDE_PORT / PI_IDE_AUTH / PI_IDE_LOCKFILE into the process
// environment. On session start we read those vars and log what we found.
//
// `pi` is intentionally typed `any`: the real types come from the pi-provided
// peer packages (@earendil-works/pi-*), which are kept `external` in the
// esbuild bundle and wired up in Phase 3 along with the actual tools.

export default function (pi: any): void {
  pi.on("session_start", () => {
    const port = process.env.PI_IDE_PORT;
    const auth = process.env.PI_IDE_AUTH;
    if (port && auth) {
      console.error(
        `[pi-nvim-bridge] discovered pi-panel.nvim WebSocket server on ` +
          `127.0.0.1:${port} (Phase 2 stub — not connecting yet)`,
      );
    } else {
      console.error(
        "[pi-nvim-bridge] PI_IDE_PORT/PI_IDE_AUTH not set — " +
          "this pi was not launched by pi-panel.nvim",
      );
    }
  });
}
