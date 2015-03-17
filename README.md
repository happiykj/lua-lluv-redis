# lua-lluv-redis
[![Licence](http://img.shields.io/badge/Licence-MIT-brightgreen.svg)](LICENSE)
[![Build Status](https://travis-ci.org/moteus/lua-lluv-redis.svg?branch=master)](https://travis-ci.org/moteus/lua-lluv-redis)
[![Coverage Status](https://coveralls.io/repos/moteus/lua-lluv-redis/badge.svg)](https://coveralls.io/r/moteus/lua-lluv-redis)

##Usage

### lluv client
```Lua
redis.Connection.new():open(function(cli)
  cli:ping(print)
  cli:quit(print)
end)
```

### basic transaction
```Lua
cli:open(function()
  cli:multi(function(cli, err, data) -- begin transaction
    print("MULTI:", data)

    -- we can proceed each command in separate callback
    cli:set("a", "10", function(cli, err, data)
      print("SET:", data)
    end)

    cli:ping() --or we can ignore command callback

    cli:exec(function(cli, err, res) -- end transaction
      -- and proceed all results in exec callback
      for k, v in ipairs(res) do print("CMD #" .. k, v) end

    end)
  end)
end)
```

### Using low-level parser
You can use low-level parser to use other IO library.

```Lua
-- Using stream decoder with lluv
local uv          = require "lluv"
local RedisStream = require "lluv.redis.stream"

uv.tcp():connect("127.0.0.1", 6379, function(cli, err)
  local stream stream = RedisStream.new()
  :on_command(function(self, msg, cb)
    return cli:write(msg, function(_, err)
      if err then return stream:halt(err) end
    end)
  end)
  :on_halt(function(self, err)
    cli:close()
  end)

  cli:start_read(function(cli, err, data)
    if err then return stream:halt(err) end
    stream
      :append(data)
      :execute()
  end)

  stream:command("PING", function(...)
    print("PING:", ...)
  end)

  local msg = '"Hello, world!!!"'
  stream:command({"ECHO", msg}, function(...)
    print("ECHO:", ...)
  end)

  stream:command("PING2", function(...)
    print("ERROR:", ...)
  end)

  stream:command("QUIT", function(...)
    print("QUIT:", ...)
  end)

end)

uv.run(debug.traceback)
```
