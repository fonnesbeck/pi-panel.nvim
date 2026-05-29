"use strict";
// Self-contained WebSocket client for the integration test. Uses node:net +
// node:crypto only (no `ws` dependency) so it is hermetic and can set the
// custom x-pi-ide-authorization header (which Node's global WebSocket cannot).
//
//   node ws_client.js <port> [token]
// Prints a single JSON line: {ok:true,result:...} on success, {ok:false,error}
// on failure. Exit 0 on success, non-zero otherwise.

const net = require("node:net");
const crypto = require("node:crypto");

const port = Number(process.argv[2]);
const token = process.argv[3]; // undefined => omit the auth header

const key = crypto.randomBytes(16).toString("base64");
const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
const expectedAccept = crypto.createHash("sha1").update(key + GUID).digest("base64");

function done(obj, code) {
  process.stdout.write(JSON.stringify(obj) + "\n");
  process.exit(code);
}
const fail = (msg) => done({ ok: false, error: msg }, 2);

function maskFrame(opcode, text) {
  const data = Buffer.from(text, "utf8");
  const len = data.length;
  const mask = crypto.randomBytes(4);
  let header;
  if (len < 126) {
    header = Buffer.from([0x80 | opcode, 0x80 | len]);
  } else {
    header = Buffer.from([0x80 | opcode, 0x80 | 126, (len >> 8) & 0xff, len & 0xff]);
  }
  const masked = Buffer.alloc(len);
  for (let i = 0; i < len; i++) masked[i] = data[i] ^ mask[i % 4];
  return Buffer.concat([header, mask, masked]);
}

function decodeFrame(b) {
  if (b.length < 2) return null;
  const opcode = b[0] & 0x0f;
  let len = b[1] & 0x7f;
  let pos = 2;
  if (len === 126) { len = b.readUInt16BE(2); pos = 4; }
  else if (len === 127) { len = Number(b.readBigUInt64BE(2)); pos = 10; }
  if (b.length < pos + len) return null;
  return { opcode, payload: b.slice(pos, pos + len).toString("utf8") };
}

const sock = net.connect(port, "127.0.0.1");
sock.setTimeout(4000, () => fail("timeout"));
sock.on("error", (e) => fail("socket error: " + e.message));

let buf = Buffer.alloc(0);
let upgraded = false;

sock.on("connect", () => {
  const lines = [
    "GET / HTTP/1.1",
    "Host: 127.0.0.1:" + port,
    "Upgrade: websocket",
    "Connection: Upgrade",
    "Sec-WebSocket-Key: " + key,
    "Sec-WebSocket-Version: 13",
  ];
  if (token) lines.push("x-pi-ide-authorization: " + token);
  sock.write(lines.join("\r\n") + "\r\n\r\n");
});

sock.on("data", (chunk) => {
  buf = Buffer.concat([buf, chunk]);

  if (!upgraded) {
    const idx = buf.indexOf("\r\n\r\n");
    if (idx === -1) return;
    const head = buf.slice(0, idx).toString();
    if (!/^HTTP\/1\.1 101/.test(head)) {
      return fail("not upgraded: " + head.split("\r\n")[0]);
    }
    if (!head.includes("Sec-WebSocket-Accept: " + expectedAccept)) {
      return fail("bad Sec-WebSocket-Accept");
    }
    upgraded = true;
    buf = buf.slice(idx + 4);
    const req = JSON.stringify({
      jsonrpc: "2.0", id: "init-1", method: "initialize",
      params: { protocolVersion: 1, supportedTools: [] },
    });
    sock.write(maskFrame(0x1, req));
  }

  if (upgraded) {
    const f = decodeFrame(buf);
    if (f) {
      let resp;
      try { resp = JSON.parse(f.payload); } catch (e) { return fail("bad json: " + f.payload); }
      done({ ok: true, result: resp.result }, 0);
    }
  }
});
