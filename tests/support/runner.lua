-- Minimal zero-dependency test harness, run via `nvim --headless -l tests/run.lua`.
-- Provides describe/it plus a small set of assertions. Not production code.

local M = {}

local suites = {} -- { { name=..., tests={ { name=..., fn=... } } } }
local current

function M.describe(name, fn)
  current = { name = name, tests = {} }
  table.insert(suites, current)
  fn()
  current = nil
end

function M.it(name, fn)
  assert(current, "it() must be called inside describe()")
  table.insert(current.tests, { name = name, fn = fn })
end

-- ---- assertions -----------------------------------------------------------

local function fail(msg)
  error({ __test_failure = true, message = msg }, 2)
end

local function pretty(v)
  if type(v) == "string" then
    return string.format("%q", v)
  end
  return tostring(v)
end

local function deep_equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

function M.eq(actual, expected, msg)
  if not deep_equal(actual, expected) then
    fail((msg and (msg .. ": ") or "")
      .. "expected " .. pretty(expected) .. ", got " .. pretty(actual))
  end
end

function M.ne(actual, unexpected, msg)
  if deep_equal(actual, unexpected) then
    fail((msg and (msg .. ": ") or "") .. "expected value to differ from " .. pretty(unexpected))
  end
end

function M.is_true(v, msg)
  if v ~= true then fail((msg and (msg .. ": ") or "") .. "expected true, got " .. pretty(v)) end
end

function M.is_nil(v, msg)
  if v ~= nil then fail((msg and (msg .. ": ") or "") .. "expected nil, got " .. pretty(v)) end
end

function M.truthy(v, msg)
  if not v then fail((msg and (msg .. ": ") or "") .. "expected truthy, got " .. pretty(v)) end
end

-- Run `fn` and assert it raises an error whose message contains `pattern`
-- (plain substring match). Returns the error message.
function M.error_contains(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then fail((msg and (msg .. ": ") or "") .. "expected error containing " .. pretty(pattern) .. ", but no error raised") end
  local text = type(err) == "table" and err.message or tostring(err)
  if not string.find(text, pattern, 1, true) then
    fail((msg and (msg .. ": ") or "") .. "expected error containing " .. pretty(pattern) .. ", got " .. pretty(text))
  end
  return text
end

-- ---- runner ---------------------------------------------------------------

local RED = "\27[31m"
local GREEN = "\27[32m"
local RESET = "\27[0m"

function M.run()
  local passed, failed = 0, 0
  local failures = {}
  for _, suite in ipairs(suites) do
    print(suite.name)
    for _, test in ipairs(suite.tests) do
      local ok, err = pcall(test.fn)
      if ok then
        passed = passed + 1
        print("  " .. GREEN .. "ok" .. RESET .. "   " .. test.name)
      else
        failed = failed + 1
        local message = (type(err) == "table" and err.message) or tostring(err)
        print("  " .. RED .. "FAIL" .. RESET .. " " .. test.name)
        print("       " .. message)
        table.insert(failures, suite.name .. " > " .. test.name .. ": " .. message)
      end
    end
  end
  print(string.format("\n%d passed, %d failed", passed, failed))
  return failed
end

return M
