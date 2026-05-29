// index.ts
function index_default(pi) {
  pi.on("session_start", () => {
    const port = process.env.PI_IDE_PORT;
    const auth = process.env.PI_IDE_AUTH;
    if (port && auth) {
      console.error(
        `[pi-nvim-bridge] discovered pi-panel.nvim WebSocket server on 127.0.0.1:${port} (Phase 2 stub \u2014 not connecting yet)`
      );
    } else {
      console.error(
        "[pi-nvim-bridge] PI_IDE_PORT/PI_IDE_AUTH not set \u2014 this pi was not launched by pi-panel.nvim"
      );
    }
  });
}
export {
  index_default as default
};
