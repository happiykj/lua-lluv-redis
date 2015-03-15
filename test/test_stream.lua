pcall(require, "luacov")

local RedisStream = require "lluv.redis.stream"

local lunit = lunit

local RUN = lunit and function()end or function ()
  local res = lunit.run()
  if res.errors + res.failed > 0 then
    os.exit(-1)
  end
  return os.exit(0)
end

lunit = require "lunit"

local TEST_CASE  = assert(lunit.TEST_CASE)
local skip       = lunit.skip or function() end
local IT         = function(m)
  return setmetatable(m, {__call = function(self, describe, fn)
    self["test " .. describe] = fn
  end})
end

local function nreturn(...)
  return select("#", ...), ...
end

local function PASS() return true end

local function FALSE() return false end

local function CMD(t)if type(t)=="table"then return table.concat(t)end return t end

local is_equal do
  local cmp_t
  local function cmp_v(v1,v2)
    local flag = true
    if type(v1) == 'table' then
      flag = (type(v2) == 'table') and cmp_t(v1, v2)
    else
      flag = (v1 == v2)
    end
    return flag
  end

  function cmp_t(t1,t2)
    for k in pairs(t2)do
      if t1[k] == nil then
        return false
      end
    end
    for k,v in pairs(t1)do
      if not cmp_v(t2[k],v) then 
        return false 
      end
    end
    return true
  end

  is_equal = cmp_v
end

local pcall, error, type, table = pcall, error, type, table

local ENABLE = true

local _ENV = TEST_CASE'redis stream encoder/decoder' if ENABLE then

local it = IT(_ENV or _M)

local stream

function setup()
  stream = assert(RedisStream.new())
end

it("provide public API", function()
  assert_function(stream.execute)
  assert_function(stream.append)
  assert_function(stream.command)
  assert_function(stream.pipeline)
end)

it("should fail without on_command callback", function()
  assert_error(function() stream:command("PING", function() end) end)
end)

it("on_command callback signature", function()
  local f = false
  stream:on_command(function(...)
    f = true
    local n, a, b, c = nreturn(...)
    assert_equal(3, n)
    assert_equal(stream, a)
    if type(b) ~= "string" then assert_table(b) end
    assert_equal(PASS, c)
  end)

  stream:command("PING", PASS)
  assert_true(f)
end)

it("should fail without command callback", function()
  stream:on_command(PASS)
  assert_error(function() stream:command("PING") end)
end)

it("should encode basic command as string", function()
  local msg
  stream:on_command(function(_, cmd)
    msg = assert(cmd)
  end)

  stream:command("PING", PASS)
  assert_equal("PING\r\n", msg)
end)

it("should pass any command", function()
  local msg
  stream:on_command(function(_, cmd)
    msg = assert(cmd)
  end)

  stream:command("***", PASS)
  assert_equal("***\r\n", msg)
end)

it("should encode command with string args", function()
  local msg
  stream:on_command(function(_, cmd)
    msg = CMD(cmd)
  end)

  stream:command({"ECHO", "Hello world"}, PASS)

  assert_equal("*2\r\n$4\r\nECHO\r\n$11\r\nHello world\r\n", msg)
end)

it("should encode command with array args", function()
  local msg
  stream:on_command(function(_, cmd)
    msg = CMD(cmd)
  end)

  local res = table.concat{
    "*2\r\n",
      "$4\r\n" .. "ECHO\r\n",
      "*2\r\n",
        "*3\r\n",
          ":1\r\n",
          ":2\r\n",
          ":3\r\n",
        "*3\r\n",
          "$3\r\n" .. "Foo\r\n",
          "$3\r\n" .. "Bar\r\n",
          "$6\r\n" .. "foobar\r\n",
  }
  local arg = {{1,2,3},{'Foo','Bar','foobar'}}

  stream:command({"ECHO", arg} , PASS)

  assert_equal(res, msg)
end)

it("should decode pass", function()
  stream:on_command(PASS)

  local res
  stream:command("PING", function(self, err, data)
    assert_nil(err)
    res = data
  end)

  stream:append("+PONG\r\n"):execute()

  assert_equal("PONG", res)
end)

it("should decode error", function()
  stream:on_command(PASS)

  local err, res
  stream:command("PING", function(self, ...)
    err, res = ...
  end)

  stream:append("-ERR unknown command 'PING2'\r\n"):execute()

  assert_equal("ERR", err)
  assert_equal("unknown command 'PING2'", res)
end)

it("should decode number", function()
  stream:on_command(PASS)

  local res
  stream:command("***", function(self, err, data)
    assert_nil(err)
    res = data
  end)

  stream:append(":12345\r\n"):execute()

  assert_equal(12345, res)
end)

it("should decode bulk", function()
  stream:on_command(PASS)

  local res
  stream:command("***", function(self, err, data)
    assert_nil(err)
    res = data
  end)

  stream:append("$5\r\nhello\r\n"):execute()

  assert_equal("hello", res)
end)

it("should decode array", function()
  stream:on_command(PASS)

  local res
  stream:command("***", function(self, err, data)
    assert_nil(err)
    res = data
  end)

  stream:append("*2\r\n")
  stream:append("*3\r\n")
  stream:append(":1\r\n")
  stream:append(":2\r\n")
  stream:append(":3\r\n")
  stream:append("*3\r\n")
  stream:append("+Foo\r\n")
  stream:append("-Bar\r\n")
  stream:append("$6\r\n")
  stream:append("foobar\r\n")

  stream:execute()

  assert(is_equal({{1,2,3},{'Foo','Bar','foobar'}}, res))
end)

it("should decode array by chunks", function()
  stream:on_command(PASS)

  local res
  stream:command("***", function(self, err, data)
    assert_nil(err)
    res = data
  end)

  local str = table.concat{
    "*2\r\n",
      "*3\r\n",
        ":1\r\n",
        ":2\r\n",
        ":3\r\n",
      "*3\r\n",
        "+Foo\r\n",
        "-Bar\r\n",
        "$6\r\n",
          "foobar\r\n",
  }

  for i = 1, #str - 1 do
    local ch = str:sub(i, i)
    stream:append(ch):execute()
    assert_nil(res)
  end
  stream:append(str:sub(-1)):execute()

  assert(is_equal({{1,2,3},{'Foo','Bar','foobar'}}, res))
end)

it("should decode bulk by chunks", function()
  stream:on_command(PASS)

  local res
  stream:command("***", function(self, err, data)
    assert_nil(err)
    res = data
  end)

  local str = "$6\r\n" .. "foobar\r\n"

  for i = 1, #str - 1 do
    local ch = str:sub(i, i)
    stream:append(ch):execute()
    assert_nil(res)
  end
  stream:append(str:sub(-1)):execute()

  assert_equal('foobar', res)
end)

it("pipeline should calls each callback", function()
  stream:on_command(PASS)

  local i = 0
  stream:pipeline("PING\r\nPING\r\n", {
    function() assert_equal(0, i) i = i + 1 end;
    function() assert_equal(1, i) i = i + 1 end;
  })

  stream:append("+PONG1\r\n")
  stream:append("+PONG2\r\n")

  stream:execute()

  assert_equal(2, i)
end)

it("pipeline should decodes stream by chunks", function()
  stream:on_command(PASS)

  local i = 0
  local res 
  stream:pipeline("PING\r\nPING\r\n", {
    function(_, err, data) assert_equal(0, i) i = i + 1 res = data end;
    function(_, err, data) assert_equal(1, i) i = i + 1 res = data end;
  })

  stream:append("+PONG1\r\n"):execute()
  assert_equal(1, i)
  assert_equal(res, "PONG1")

  stream:append("+PONG2\r\n"):execute()
  assert_equal(2, i)
  assert_equal(res, "PONG2")
end)

it("halt should calls every callback", function()
  local ERR = {}
  local called = {}

  stream:on_command(PASS)

  stream:command("***", function(_, err)
    assert_equal(ERR, err)
    called[1] = true
  end)
  
  stream:command("***", function(_, err)
    assert_equal(ERR, err)
    called[2] = true
  end)
  
  stream:command("***", function(_, err)
    assert_equal(ERR, err)
    called[3] = true
  end)

  stream:halt(ERR)

  assert_true(called[1])
  assert_true(called[2])
  assert_true(called[3])
end)

end -- test case

RUN()
