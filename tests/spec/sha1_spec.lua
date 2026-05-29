local t = require("support.runner")
local utils = require("pi-panel.server.utils")

-- sha1 returns a raw 20-byte digest; convert to lowercase hex for comparison.
local function hex(raw)
  return (raw:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

t.describe("sha1", function()
  -- FIPS 180 / RFC 3174 test vectors
  t.it("hashes the empty string", function()
    t.eq(hex(utils.sha1("")), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
  end)
  t.it("hashes 'abc'", function()
    t.eq(hex(utils.sha1("abc")), "a9993e364706816aba3e25717850c26c9cd0d89d")
  end)
  t.it("hashes the 56-char multi-block vector", function()
    local msg = "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"
    t.eq(hex(utils.sha1(msg)), "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
  end)
  t.it("hashes a 64-byte (exact block) input", function()
    -- exercises the padding path where a full extra block is needed
    local msg = string.rep("a", 64)
    t.eq(hex(utils.sha1(msg)), "0098ba824b5c16427bd7a1122a5a442a25ec644d")
  end)
  t.it("produces a 20-byte digest", function()
    t.eq(#utils.sha1("anything"), 20)
  end)
end)
