# 3. Extension distribution: committed self-contained esbuild bundle

Status: accepted (revised in Phase 3 against the real pi 0.77 loader)

## Context

The `pi-nvim-bridge` extension is TypeScript and has one real runtime
dependency (`ws`, for a WebSocket client that can set a custom auth header —
Node's global `WebSocket` cannot). pi loads `-e` extensions through jiti. We
need zero-install distribution.

## Decision

Ship a single committed `dist/index.js` produced by esbuild, loaded via
`pi -e <abs>/dist/index.js`. **Both `ws` and `typebox` are inlined.** Only the
type-only pi packages (`@earendil-works/pi-*`) stay external, and since they are
imported with `import type`, esbuild erases them.

## Why typebox is inlined (the plan originally kept it external)

- pi's loader uses jiti with `tryNative`, which native-`import`s a pre-bundled
  `.js`. Native import bypasses jiti's peer-dependency `alias` map, so a bare
  `import { Type } from "typebox"` is unresolvable for end users (who get only
  `dist/index.js`, no `node_modules`) — verified `ERR_MODULE_NOT_FOUND`.
- typebox 1.x emits **plain JSON Schema** objects (no symbol/`Kind` markers), so
  there is no module-identity concern with bundling our own copy.

## Consequences

- The ESM bundle needs a `createRequire` banner so the inlined CJS `ws` can
  `require()` Node built-ins.
- Distribution is a single self-contained file; end users never run `npm`.
- Contributors run `make build` after changing the source; CI runs `npm audit`.
