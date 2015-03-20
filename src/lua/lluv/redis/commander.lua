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

local ut     = require "lluv.utils"
local Stream = require "lluv.redis.stream"

--- Notes
-- Request is array of strings.
-- You can not pass number (:123), NULL(*-1), basic string (+HELLO) or any other type.

local function dummy()end

local function is_callable(f) return (type(f) == 'function') and f end

local pack_args = function(...)
  local n    = select("#", ...)
  local args = {...}
  local cb   = args[n]
  if is_callable(cb) then args[n] = nil else cb = dummy end
  if #args == 1 then args = args[1] end
  return args, cb
end

local any = pack_args

local eval = function(...)
  local args, cb = pack_args(...)
  if type(args[3]) == 'table' then
    table.insert(args, 3, tostring(#args[3]))
  end
  return args, cb
end

local sbool = function(err, resp)
  return err, resp == 'OK'
end;

local nbool = function(err, resp)
    return err, resp == 1
  end;

local hash  = function(err, resp)
  local res = {}
  for i = 1, resp.n or #resp, 2 do
      res[ resp[i] ] = resp[i + 1]
    end
  return err, res
end;

local pass  = function(err, resp)
  return err, resp
end;


local RedisPipeline

local RedisCommander = ut.class() do

RedisCommander._commands = {}

function RedisCommander:__init(stream)
  self._stream   = stream or Stream.new()
  self._commands = {}

  return self
end

function RedisCommander:add_command(name, opt, request, response)
  name = name:upper()

  local opt, request, response = opt or {}

  if opt.generate then
    name, request, response = opt.generate(name, opt)
  end

  request  = opt.request  or any
  response = opt.response or pass
  name     = ut.split_first(name, ' ', true)

  local decoder = function(err, data)
    if err then return err, data end --! @todo Build error object
    return response(err, data)
  end

  self[name:lower()] = function(self, ...)
    local cmd, cb = request(name, ...)
    return self._stream:command(cmd, cb, decoder)
  end

  self["_pipeline_" .. name:lower()] = function(self, ...)
    local cmd, cb = request(name, ...)
    return self._stream:pipeline_command(cmd, cb, decoder)
  end

  self._commands[name] = true

  return self
end

function RedisCommander:each_command(fn)
  for cmd in pairs(RedisCommander._commands) do fn(cmd, true) end
  if self ~= RedisCommander then
    for cmd in pairs(self._commands) do fn(cmd, false) end
  end
  return self
end

function RedisCommander:_pipeline(...)
  return self._stream:pipeline(...)
end

function RedisCommander:pipeline()
  return RedisPipeline.new(self)
end

RedisCommander
  :add_command('APPEND',                        {request = any,    response = pass  }   )	--	APPEND	key	value
  :add_command('AUTH',                          {request = any,    response = pass  }   )	--	AUTH	password
  :add_command('BGREWRITEAOF',                  {request = any,    response = pass  }   )	--	BGREWRITEAOF
  :add_command('BGSAVE',                        {request = any,    response = pass  }   )	--	BGSAVE
  :add_command('BITCOUNT',                      {request = any,    response = pass  }   )	--	BITCOUNT	key	[start end]
  :add_command('BITOP',                         {request = any,    response = pass  }   )	--	BITOP	operation	destkey	key [key ...]
  :add_command('BITPOS',                        {request = any,    response = pass  }   )	--	BITPOS	key	bit	[start]	[end]
  :add_command('BLPOP',                         {request = any,    response = pass  }   )	--	BLPOP	key [key ...]	timeout
  :add_command('BRPOP',                         {request = any,    response = pass  }   )	--	BRPOP	key [key ...]	timeout
  :add_command('BRPOPLPUSH',                    {request = any,    response = pass  }   )	--	BRPOPLPUSH	source	destination	timeout
  :add_command('CLIENT KILL',                   {request = any,    response = pass  }   )	--	CLIENT KILL	[ip:port]	[ID client-id]	[TYPE normal|slave|pubsub]	[ADDR ip:port]	[SKIPME yes/no]
  :add_command('CLIENT LIST',                   {request = any,    response = pass  }   )	--	CLIENT LIST
  :add_command('CLIENT GETNAME',                {request = any,    response = pass  }   )	--	CLIENT GETNAME
  :add_command('CLIENT PAUSE',                  {request = any,    response = pass  }   )	--	CLIENT PAUSE	timeout
  :add_command('CLIENT SETNAME',                {request = any,    response = pass  }   )	--	CLIENT SETNAME	connection-name
  :add_command('CLUSTER ADDSLOTS',              {request = any,    response = pass  }   )	--	CLUSTER ADDSLOTS	slot [slot ...]
  :add_command('CLUSTER COUNT-FAILURE-REPORTS', {request = any,    response = pass  }   )	--	CLUSTER COUNT-FAILURE-REPORTS	node-id
  :add_command('CLUSTER COUNTKEYSINSLOT',       {request = any,    response = pass  }   )	--	CLUSTER COUNTKEYSINSLOT	slot
  :add_command('CLUSTER DELSLOTS',              {request = any,    response = pass  }   )	--	CLUSTER DELSLOTS	slot [slot ...]
  :add_command('CLUSTER FORGET',                {request = any,    response = pass  }   )	--	CLUSTER FORGET	node-id
  :add_command('CLUSTER GETKEYSINSLOT',         {request = any,    response = pass  }   )	--	CLUSTER GETKEYSINSLOT	slot	count
  :add_command('CLUSTER INFO',                  {request = any,    response = pass  }   )	--	CLUSTER INFO
  :add_command('CLUSTER KEYSLOT',               {request = any,    response = pass  }   )	--	CLUSTER KEYSLOT	key
  :add_command('CLUSTER MEET',                  {request = any,    response = pass  }   )	--	CLUSTER MEET	ip	port
  :add_command('CLUSTER NODES',                 {request = any,    response = pass  }   )	--	CLUSTER NODES
  :add_command('CLUSTER REPLICATE',             {request = any,    response = pass  }   )	--	CLUSTER REPLICATE	node-id
  :add_command('CLUSTER SAVECONFIG',            {request = any,    response = pass  }   )	--	CLUSTER SAVECONFIG
  :add_command('CLUSTER SETSLOT',               {request = any,    response = pass  }   )	--	CLUSTER SETSLOT	slot	IMPORTING|MIGRATING|STABLE|NODE	[node-id]
  :add_command('CLUSTER SLAVES',                {request = any,    response = pass  }   )	--	CLUSTER SLAVES	node-id
  :add_command('CLUSTER SLOTS',                 {request = any,    response = pass  }   )	--	CLUSTER SLOTS
  :add_command('COMMAND',                       {request = any,    response = pass  }   )	--	COMMAND
  :add_command('COMMAND COUNT',                 {request = any,    response = pass  }   )	--	COMMAND COUNT
  :add_command('COMMAND GETKEYS',               {request = any,    response = pass  }   )	--	COMMAND GETKEYS
  :add_command('COMMAND INFO',                  {request = any,    response = pass  }   )	--	COMMAND INFO	command-name [command-name ...]
  :add_command('CONFIG GET',                    {request = any,    response = pass  }   )	--	CONFIG GET	parameter
  :add_command('CONFIG REWRITE',                {request = any,    response = pass  }   )	--	CONFIG REWRITE
  :add_command('CONFIG SET',                    {request = any,    response = pass  }   )	--	CONFIG SET	parameter	value
  :add_command('CONFIG RESETSTAT',              {request = any,    response = pass  }   )	--	CONFIG RESETSTAT
  :add_command('DBSIZE',                        {request = any,    response = pass  }   )	--	DBSIZE
  :add_command('DEBUG OBJECT',                  {request = any,    response = pass  }   )	--	DEBUG OBJECT	key
  :add_command('DEBUG SEGFAULT',                {request = any,    response = pass  }   )	--	DEBUG SEGFAULT
  :add_command('DECR',                          {request = any,    response = pass  }   )	--	DECR	key
  :add_command('DECRBY',                        {request = any,    response = pass  }   )	--	DECRBY	key	decrement
  :add_command('DEL',                           {request = any,    response = pass  }   )	--	DEL	key [key ...]
  :add_command('DISCARD',                       {request = any,    response = pass  }   )	--	DISCARD
  :add_command('DUMP',                          {request = any,    response = pass  }   )	--	DUMP	key
  :add_command('ECHO',                          {request = any,    response = pass  }   )	--	ECHO	message
  :add_command('EVAL',                          {request = eval,   response = pass  }   )	--*	EVAL	script	numkeys	key [key ...]	arg [arg ...]
  :add_command('EVALSHA',                       {request = eval,   response = pass  }   )	--*	EVALSHA	sha1	numkeys	key [key ...]	arg [arg ...]
  :add_command('EXEC',                          {request = any,    response = pass  }   )	--	EXEC
  :add_command('EXISTS',                        {request = any,    response = nbool }   )	--	EXISTS	key
  :add_command('EXPIRE',                        {request = any,    response = pass  }   )	--	EXPIRE	key	seconds
  :add_command('EXPIREAT',                      {request = any,    response = pass  }   )	--	EXPIREAT	key	timestamp
  :add_command('FLUSHALL',                      {request = any,    response = pass  }   )	--	FLUSHALL
  :add_command('FLUSHDB',                       {request = any,    response = pass  }   )	--	FLUSHDB
  :add_command('GET',                           {request = any,    response = pass  }   )	--	GET	key
  :add_command('GETBIT',                        {request = any,    response = pass  }   )	--	GETBIT	key	offset
  :add_command('GETRANGE',                      {request = any,    response = pass  }   )	--	GETRANGE	key	start	end
  :add_command('GETSET',                        {request = any,    response = pass  }   )	--	GETSET	key	value
  :add_command('HDEL',                          {request = any,    response = pass  }   )	--	HDEL	key	field [field ...]
  :add_command('HEXISTS',                       {request = any,    response = pass  }   )	--	HEXISTS	key	field
  :add_command('HGET',                          {request = any,    response = pass  }   )	--	HGET	key	field
  :add_command('HGETALL',                       {request = any,    response = hash  }   )	--	HGETALL	key
  :add_command('HINCRBY',                       {request = any,    response = pass  }   )	--	HINCRBY	key	field	increment
  :add_command('HINCRBYFLOAT',                  {request = any,    response = pass  }   )	--	HINCRBYFLOAT	key	field	increment
  :add_command('HKEYS',                         {request = any,    response = pass  }   )	--	HKEYS	key
  :add_command('HLEN',                          {request = any,    response = pass  }   )	--	HLEN	key
  :add_command('HMGET',                         {request = any,    response = pass  }   )	--	HMGET	key	field [field ...]
  :add_command('HMSET',                         {request = any,    response = pass  }   )	--	HMSET	key	field value [field value ...]
  :add_command('HSET',                          {request = any,    response = pass  }   )	--	HSET	key	field	value
  :add_command('HSETNX',                        {request = any,    response = pass  }   )	--	HSETNX	key	field	value
  :add_command('HSTRLEN',                       {request = any,    response = pass  }   )	--	HSTRLEN	key	field
  :add_command('HVALS',                         {request = any,    response = pass  }   )	--	HVALS	key
  :add_command('INCR',                          {request = any,    response = pass  }   )	--	INCR	key
  :add_command('INCRBY',                        {request = any,    response = pass  }   )	--	INCRBY	key	increment
  :add_command('INCRBYFLOAT',                   {request = any,    response = pass  }   )	--	INCRBYFLOAT	key	increment
  :add_command('INFO',                          {request = any,    response = pass  }   )	--	INFO	[section]
  :add_command('KEYS',                          {request = any,    response = pass  }   )	--	KEYS	pattern
  :add_command('LASTSAVE',                      {request = any,    response = pass  }   )	--	LASTSAVE
  :add_command('LINDEX',                        {request = any,    response = pass  }   )	--	LINDEX	key	index
  :add_command('LINSERT',                       {request = any,    response = pass  }   )	--	LINSERT	key	BEFORE|AFTER	pivot	value
  :add_command('LLEN',                          {request = any,    response = pass  }   )	--	LLEN	key
  :add_command('LPOP',                          {request = any,    response = pass  }   )	--	LPOP	key
  :add_command('LPUSH',                         {request = any,    response = pass  }   )	--	LPUSH	key	value [value ...]
  :add_command('LPUSHX',                        {request = any,    response = pass  }   )	--	LPUSHX	key	value
  :add_command('LRANGE',                        {request = any,    response = pass  }   )	--	LRANGE	key	start	stop
  :add_command('LREM',                          {request = any,    response = pass  }   )	--	LREM	key	count	value
  :add_command('LSET',                          {request = any,    response = pass  }   )	--	LSET	key	index	value
  :add_command('LTRIM',                         {request = any,    response = pass  }   )	--	LTRIM	key	start	stop
  :add_command('MGET',                          {request = any,    response = pass  }   )	--	MGET	key [key ...]
  :add_command('MIGRATE',                       {request = any,    response = pass  }   )	--	MIGRATE	host	port	key	destination-db	timeout	[COPY]	[REPLACE]
  :add_command('MONITOR',                       {request = any,    response = pass  }   )	--	MONITOR
  :add_command('MOVE',                          {request = any,    response = pass  }   )	--	MOVE	key	db
  :add_command('MSET',                          {request = any,    response = pass  }   )	--	MSET	key value [key value ...]
  :add_command('MSETNX',                        {request = any,    response = pass  }   )	--	MSETNX	key value [key value ...]
  :add_command('MULTI',                         {request = any,    response = pass  }   )	--	MULTI
  :add_command('OBJECT',                        {request = any,    response = pass  }   )	--	OBJECT	subcommand	[arguments [arguments ...]]
  :add_command('PERSIST',                       {request = any,    response = pass  }   )	--	PERSIST	key
  :add_command('PEXPIRE',                       {request = any,    response = pass  }   )	--	PEXPIRE	key	milliseconds
  :add_command('PEXPIREAT',                     {request = any,    response = pass  }   )	--	PEXPIREAT	key	milliseconds-timestamp
  :add_command('PFADD',                         {request = any,    response = pass  }   )	--	PFADD	key	element [element ...]
  :add_command('PFCOUNT',                       {request = any,    response = pass  }   )	--	PFCOUNT	key [key ...]
  :add_command('PFMERGE',                       {request = any,    response = pass  }   )	--	PFMERGE	destkey	sourcekey [sourcekey ...]
  :add_command('PING',                          {request = any,    response = pass  }   )	--	PING
  :add_command('PSETEX',                        {request = any,    response = pass  }   )	--	PSETEX	key	milliseconds	value
  :add_command('PSUBSCRIBE',                    {request = any,    response = pass  }   )	--	PSUBSCRIBE	pattern [pattern ...]
  :add_command('PUBSUB',                        {request = any,    response = pass  }   )	--	PUBSUB	subcommand	[argument [argument ...]]
  :add_command('PTTL',                          {request = any,    response = pass  }   )	--	PTTL	key
  :add_command('PUBLISH',                       {request = any,    response = pass  }   )	--	PUBLISH	channel	message
  :add_command('PUNSUBSCRIBE',                  {request = any,    response = pass  }   )	--	PUNSUBSCRIBE	[pattern [pattern ...]]
  :add_command('QUIT',                          {request = any,    response = pass  }   )	--	QUIT
  :add_command('RANDOMKEY',                     {request = any,    response = pass  }   )	--	RANDOMKEY
  :add_command('RENAME',                        {request = any,    response = pass  }   )	--	RENAME	key	newkey
  :add_command('RENAMENX',                      {request = any,    response = pass  }   )	--	RENAMENX	key	newkey
  :add_command('RESTORE',                       {request = any,    response = pass  }   )	--	RESTORE	key	ttl	serialized-value	[REPLACE]
  :add_command('ROLE',                          {request = any,    response = pass  }   )	--	ROLE
  :add_command('RPOP',                          {request = any,    response = pass  }   )	--	RPOP	key
  :add_command('RPOPLPUSH',                     {request = any,    response = pass  }   )	--	RPOPLPUSH	source	destination
  :add_command('RPUSH',                         {request = any,    response = pass  }   )	--	RPUSH	key	value [value ...]
  :add_command('RPUSHX',                        {request = any,    response = pass  }   )	--	RPUSHX	key	value
  :add_command('SADD',                          {request = any,    response = pass  }   )	--	SADD	key	member [member ...]
  :add_command('SAVE',                          {request = any,    response = pass  }   )	--	SAVE
  :add_command('SCARD',                         {request = any,    response = pass  }   )	--	SCARD	key
  :add_command('SCRIPT EXISTS',                 {request = any,    response = pass  }   )	--	SCRIPT EXISTS	script [script ...]
  :add_command('SCRIPT FLUSH',                  {request = any,    response = pass  }   )	--	SCRIPT FLUSH
  :add_command('SCRIPT KILL',                   {request = any,    response = pass  }   )	--	SCRIPT KILL
  :add_command('SCRIPT LOAD',                   {request = any,    response = pass  }   )	--	SCRIPT LOAD	script
  :add_command('SDIFF',                         {request = any,    response = pass  }   )	--	SDIFF	key [key ...]
  :add_command('SDIFFSTORE',                    {request = any,    response = pass  }   )	--	SDIFFSTORE	destination	key [key ...]
  :add_command('SELECT',                        {request = any,    response = pass  }   )	--	SELECT	index
  :add_command('SET',                           {request = any,    response = pass  }   )	--*	SET	key	value	[EX seconds]	[PX milliseconds]	[NX|XX]
  :add_command('SETBIT',                        {request = any,    response = pass  }   )	--	SETBIT	key	offset	value
  :add_command('SETEX',                         {request = any,    response = pass  }   )	--	SETEX	key	seconds	value
  :add_command('SETNX',                         {request = any,    response = pass  }   )	--	SETNX	key	value
  :add_command('SETRANGE',                      {request = any,    response = pass  }   )	--	SETRANGE	key	offset	value
  :add_command('SHUTDOWN',                      {request = any,    response = pass  }   )	--*	SHUTDOWN	[NOSAVE]	[SAVE]
  :add_command('SINTER',                        {request = any,    response = pass  }   )	--	SINTER	key [key ...]
  :add_command('SINTERSTORE',                   {request = any,    response = pass  }   )	--	SINTERSTORE	destination	key [key ...]
  :add_command('SISMEMBER',                     {request = any,    response = pass  }   )	--	SISMEMBER	key	member
  :add_command('SLAVEOF',                       {request = any,    response = pass  }   )	--	SLAVEOF	host	port
  :add_command('SLOWLOG',                       {request = any,    response = pass  }   )	--	SLOWLOG	subcommand	[argument]
  :add_command('SMEMBERS',                      {request = any,    response = pass  }   )	--	SMEMBERS	key
  :add_command('SMOVE',                         {request = any,    response = pass  }   )	--	SMOVE	source	destination	member
  :add_command('SORT',                          {request = any,    response = pass  }   )	--*	SORT	key	[BY pattern]	[LIMIT offset count]	[GET pattern [GET pattern ...]]	[ASC|DESC]	[ALPHA]	[STORE destination]
  :add_command('SPOP',                          {request = any,    response = pass  }   )	--	SPOP	key	[count]
  :add_command('SRANDMEMBER',                   {request = any,    response = pass  }   )	--	SRANDMEMBER	key	[count]
  :add_command('SREM',                          {request = any,    response = pass  }   )	--	SREM	key	member [member ...]
  :add_command('STRLEN',                        {request = any,    response = pass  }   )	--	STRLEN	key
  :add_command('SUBSCRIBE',                     {request = any,    response = pass  }   )	--	SUBSCRIBE	channel [channel ...]
  :add_command('SUNION',                        {request = any,    response = pass  }   )	--	SUNION	key [key ...]
  :add_command('SUNIONSTORE',                   {request = any,    response = pass  }   )	--	SUNIONSTORE	destination	key [key ...]
  :add_command('SYNC',                          {request = any,    response = pass  }   )	--	SYNC
  :add_command('TIME',                          {request = any,    response = pass  }   )	--	TIME
  :add_command('TTL',                           {request = any,    response = pass  }   )	--	TTL	key
  :add_command('TYPE',                          {request = any,    response = pass  }   )	--	TYPE	key
  :add_command('UNSUBSCRIBE',                   {request = any,    response = pass  }   )	--	UNSUBSCRIBE	[channel [channel ...]]
  :add_command('UNWATCH',                       {request = any,    response = pass  }   )	--	UNWATCH
  :add_command('WATCH',                         {request = any,    response = pass  }   )	--	WATCH	key [key ...]
  :add_command('ZADD',                          {request = any,    response = pass  }   )	--	ZADD	key	score member [score member ...]
  :add_command('ZCARD',                         {request = any,    response = pass  }   )	--	ZCARD	key
  :add_command('ZCOUNT',                        {request = any,    response = pass  }   )	--	ZCOUNT	key	min	max
  :add_command('ZINCRBY',                       {request = any,    response = pass  }   )	--	ZINCRBY	key	increment	member
  :add_command('ZINTERSTORE',                   {request = any,    response = pass  }   )	--*	ZINTERSTORE	destination	numkeys	key [key ...]	[WEIGHTS weight [weight ...]]	[AGGREGATE SUM|MIN|MAX]
  :add_command('ZLEXCOUNT',                     {request = any,    response = pass  }   )	--	ZLEXCOUNT	key	min	max
  :add_command('ZRANGE',                        {request = any,    response = pass  }   )	--	ZRANGE	key	start	stop	[WITHSCORES]
  :add_command('ZRANGEBYLEX',                   {request = any,    response = pass  }   )	--	ZRANGEBYLEX	key	min	max	[LIMIT offset count]
  :add_command('ZREVRANGEBYLEX',                {request = any,    response = pass  }   )	--	ZREVRANGEBYLEX	key	max	min	[LIMIT offset count]
  :add_command('ZRANGEBYSCORE',                 {request = any,    response = pass  }   )	--	ZRANGEBYSCORE	key	min	max	[WITHSCORES]	[LIMIT offset count]
  :add_command('ZRANK',                         {request = any,    response = pass  }   )	--	ZRANK	key	member
  :add_command('ZREM',                          {request = any,    response = pass  }   )	--	ZREM	key	member [member ...]
  :add_command('ZREMRANGEBYLEX',                {request = any,    response = pass  }   )	--	ZREMRANGEBYLEX	key	min	max
  :add_command('ZREMRANGEBYRANK',               {request = any,    response = pass  }   )	--	ZREMRANGEBYRANK	key	start	stop
  :add_command('ZREMRANGEBYSCORE',              {request = any,    response = pass  }   )	--	ZREMRANGEBYSCORE	key	min	max
  :add_command('ZREVRANGE',                     {request = any,    response = pass  }   )	--	ZREVRANGE	key	start	stop	[WITHSCORES]
  :add_command('ZREVRANGEBYSCORE',              {request = any,    response = pass  }   )	--	ZREVRANGEBYSCORE	key	max	min	[WITHSCORES]	[LIMIT offset count]
  :add_command('ZREVRANK',                      {request = any,    response = pass  }   )	--	ZREVRANK	key	member
  :add_command('ZSCORE',                        {request = any,    response = pass  }   )	--	ZSCORE	key	member
  :add_command('ZUNIONSTORE',                   {request = any,    response = pass  }   )	--*	ZUNIONSTORE	destination	numkeys	key [key ...]	[WEIGHTS weight [weight ...]]	[AGGREGATE SUM|MIN|MAX]
  :add_command('SCAN',                          {request = any,    response = pass  }   )	--	SCAN	cursor	[MATCH pattern]	[COUNT count]
  :add_command('SSCAN',                         {request = any,    response = pass  }   )	--	SSCAN	key	cursor	[MATCH pattern]	[COUNT count]
  :add_command('HSCAN',                         {request = any,    response = pass  }   )	--	HSCAN	key	cursor	[MATCH pattern]	[COUNT count]
  :add_command('ZSCAN',                         {request = any,    response = pass  }   )	--	ZSCAN	key	cursor	[MATCH pattern]	[COUNT count]
end

RedisPipeline = ut.class() do

function RedisPipeline:__init(commander)
  self._commander = assert(commander)
  self._cmd, self._arg = {},{}

  return self
end

function RedisPipeline:add_command(name)
  local n = '_pipeline_' .. name:lower()
  self[name:lower()] = function(self, ...)
    local cmd, args = self._commander[n](self._commander, ...)
    if cmd then
      self._cmd[#self._cmd + 1] = cmd
      self._arg[#self._arg + 1] = args
    end
    return self
  end
end

RedisCommander:each_command(function(name)
  RedisPipeline:add_command(name)
end)

function RedisPipeline:execute(preserve)
  self._commander:_pipeline(self._cmd, self._arg, preserve)

  if not preserve then
    self._cmd, self._arg = {}, {}
  end

  return self
end

end

return {
  new      = RedisCommander.new;
  commands = function(...) RedisCommander:each_command(...) end;
}
