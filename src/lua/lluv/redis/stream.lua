------------------------------------------------------------------
--
--  Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Copyright (C) 2015 Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Licensed according to the included 'LICENSE' document
--
--  This file is part of lua-lluv-redis library.
--
------------------------------------------------------------------

local ut = require "lluv.utils"

local NULL = {}

local RedisCmdStream = ut.class() do

local EOL  = "\r\n"
local OK   = '+'
local ERR  = '-'
local INT  = ':'
local BULK = '$'
local ARR  = '*'

local CB, STATE, DATA, CMD, DECODER = 1, 2, 3, 4, 5
local I, N = 3, 1

local function pass(err, data) return err, data end

local function decode_line(line)
  local p, d = line:sub(1, 1), line:sub(2)
  if p == '+' then return p, d end
  if p == '-' then return p, ut.split_first(d, " ", true) end
  if p == ':' then return p, tonumber(d) end
  if p == '$' then return p, tonumber(d) end
  if p == '*' then return p, tonumber(d) end
  return p, d
end

local function array_context(n)
  return {
    [0] = {n, 'line', 1}
  }
end

local function encode(t, res)
  res = res or {}

  if type(t) == "string" then
    res[#res + 1] = BULK .. #t .. EOL
    res[#res + 1] = t
    res[#res + 1] = EOL
    return res
  end

  if t == nil or t == NULL then
    res[#res + 1] = "*-1" .. EOL
    return res
  end

  if type(t) == "number" then
    res[#res + 1] = INT .. t .. EOL
    return res
  end

  local n = t.n or #t
  res[#res + 1] = "*" .. tostring(n) .. EOL
  for i = 1, n do
    encode(t[i], res)
  end

  return res
end

local function encode_cmd(t)
  if type(t) == 'string' then return t .. EOL, t end
  return encode(t), t[1]
end

local function is_callable(f) return (type(f) == 'function') and f end

local function flat(t)
  if type(t) == 'string' then return t end

  local r = {}
  for i = 1, #t do
    local v = t[i]
    if type(v) == 'string' then
      r[#r + 1] = v
    else
      for j = 1, #v do
        r[#r + 1] = v[j]
      end
    end
  end
  return r
end

function RedisCmdStream:__init(cb_self)
  self._buffer = ut.Buffer.new(EOL)
  self._queue  = ut.Queue.new()
  self._txn    = ut.Queue.new()
  self._self   = cb_self or self

  return self
end

function RedisCmdStream:_decode_array(t)
  local ctx = t[0]

  while ctx[I] <= ctx[N] do
    local i = ctx[I]
    if ctx[STATE] == 'line' then
      local line = self._buffer:read_line()
      if not line then return end
      local typ, n, ext = decode_line(line)
  
      if not typ then return end

      if typ == ARR then
        if n == -1 then
          t[i], ctx[I] = nil, i + 1
        else
          ctx[STATE], t[i] = 'array', array_context(n, t)
        end
      elseif typ == OK or typ == INT then
        t[i], ctx[I] = n, i + 1
      elseif typ == ERR then
        t[i], ctx[I] = {error = n, info = ext}, i + 1
      elseif typ == BULK then
        t[i], ctx[STATE] = n, 'array_string'
      else
        error("Unsupported Type:" .. typ)
      end
    end

    if ctx[STATE] == 'array_string' then
      local data = self._buffer:read_n(t[i])
      if not data then return end
      t[i], ctx[STATE] = data, 'array_string_eol'
    end

    if ctx[STATE] == 'array_string_eol' then
      local data = self._buffer:read_n(#EOL)
      if not data then return end
      assert(data == EOL)
      ctx[STATE], ctx[I] = 'line', i + 1
    end

    if ctx[STATE] == 'array' then
      if not self:_decode_array(t[i]) then
        return
      end
      ctx[STATE], ctx[I] = 'line', i + 1
    end
  end

  if ctx[I] > ctx[N] then
    t[0] = nil
    return true
  end
end

function RedisCmdStream:_next_data_task()
  local queue = self._queue

  while true do
    local task = queue:peek()
    if not task or task[STATE] then return task end

    local line = self._buffer:read_line()
    if not line then return end

    local cb, decoder = task[CB], task[DECODER]
    local typ, data, add = decode_line(line)
    if typ == OK then
      queue:pop()
      if data == 'QUEUED' then
        self._txn:push(task)
      else
        if task[CMD] == 'DISCARD' then
          while true do
            local task = self._txn:pop()
            if not task then break end
            task[CB](self._self, task[DECODER]('DISCARD'))
          end
        end
        cb(self._self, decoder(nil, data))
      end
    elseif typ == ERR then
      queue:pop()
      cb(self._self, decoder(data, add))
    elseif typ == INT then
      queue:pop()
      cb(self._self, decoder(nil, data))
    elseif typ == BULK then
      task[STATE], task[DATA] = 'BULK', data
    elseif typ == ARR then
      if data == -1 then
        queue:pop()

        if task[CMD] == 'EXEC' then
          while true do
            local task = self._txn:pop()
            if not task then break end
            task[CB](self._self, decoder())
          end
        end

        cb(self._self, decoder())
      else
        task[STATE], task[DATA] = 'ARR', array_context(data)
        return task
      end
    end
  end
end

function RedisCmdStream:execute()
  while true do
    local task = self:_next_data_task()
    if not task then return end

    local cb, decoder = task[CB], task[DECODER]
    if task[STATE] == 'BULK' then
      local data = self._buffer:read_n(task[DATA])
      if not data then return end
      task[STATE], task[DATA] = 'BULK_EOL', data
    elseif task[STATE] == 'ARR' then
      if not self:_decode_array(task[DATA]) then
        return
      end
      self._queue:pop()

      if task[CMD] == 'EXEC' then
        local t, i = task[DATA], 1
        while true do
          local task = self._txn:pop()
          if not task then break end

          if type(t[i]) == "table" and t[i].error then
            task[CB](self._self, decoder(t[i].error, t[i].info))
          else
            task[CB](self._self, decoder(nil, t[i]))
          end
          i = i + 1
        end
      end

      cb(self._self, decoder(nil, task[DATA]))
    end

    if task[STATE] == 'BULK_EOL' then
      local eol = self._buffer:read_n(#EOL)
      if not eol then return end
      assert(eol == EOL, eol)
      assert(task == self._queue:pop())
      cb(self._self, decoder(nil, task[DATA]))
    end

  end
end

function RedisCmdStream:append(data)
  self._buffer:append(data)
  return self
end

function RedisCmdStream:encode_command(cmd)
  return encode_cmd(cmd)
end

function RedisCmdStream:command(cmd, cb, decoder)
  assert(is_callable(cb))
  local cmd, cmd_name = self:encode_command(cmd)
  if self:_on_command(cmd, cb) then
    self._queue:push{cb, nil, nil, cmd_name, decoder or pass}
  end
  return self._self
end

function RedisCmdStream:pipeline_command(cmd, cb, decoder)
  assert(is_callable(cb))
  local cmd, cmd_name = self:encode_command(cmd)
  local task = {cb, nil, nil, cmd_name, decoder or pass}
  return cmd, task
end

function RedisCmdStream:pipeline(cmd, tasks)
  if self:_on_command(flat(cmd)) then
    for i = 1, #tasks do
      local task = tasks[i]
      self._queue:push(task)
    end
  end

  return self
end

function RedisCmdStream:halt(err)
  self:reset(err)
  if self._on_halt then self:_on_halt(err) end
  return
end

function RedisCmdStream:reset(err)
  while true do
    local task = self._queue:pop()
    if not task then break end
    task[CB](self, err)
  end

  while true do
    local task = self._txn:pop()
    if not task then break end
    task[CB](self, err)
  end

  self._buffer:reset()
  return
end

function RedisCmdStream:on_command(handler)
  self._on_command = handler
  return self
end

function RedisCmdStream:on_halt(handler)
  self._on_halt = handler
  return self
end

end

return {
  new = RedisCmdStream.new;
  NULL = NULL;
}