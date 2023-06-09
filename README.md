<!-- MDOC !-->
# LibRedis

LibRedis is a Redis client written in Elixir. It is essentially a wrapper around the [Redix](https://github.com/whatyouhide/redix) project, with added support for connection pooling and Redis cluster functionality. 
The client exposes two main APIs: `command/3` and `pipeline/3`.

中文文档 ----> [README_zh.md](https://github.com/tt67wq/lib-redis/blob/master/README_zh.md)

## NOTE:
**The implementation of the Cluster mode in production requires careful consideration and attention, as it has yet to undergo complete and rigorous testing.**

## Features
- [x] Connection pooling
- [x] Standalone mode
- [x] Cluster mode

## Installation

To use LibRedis in your Elixir project, simply add it as a dependency in your `mix.exs` file:

```elixir
defp deps do
  [
    {:lib_redis, github: "tt67wq/lib-redis"}
  ]
end
```

Then, run `mix deps.get` to install the dependency.

## Usage

### Standalone

To use LibRedis in singleton mode, you have to set your client as `:standalone` mode:

```elixir
standalone_options = [
  name: :redis,
  mode: :standalone,
  url: "redis://:pwd@localhost:6379",
  pool_size: 5
]

standalone = LibRedis.new(standalone_options)
```

Then, add the `LibRedis` application to your supervision tree:

```elixir
children = [
  {LibRedis, redis: standalone}
]
```

The `options` parameter is a keyword list that contains the connection options for Redis. The `pool_size` option specifies the number of connections in the pool.
Thanks to powerful [nimble_pool](https://github.com/dashbitco/nimble_pool), we can easily use a nimble pool to manage redis connections.

Once you have a instance, you can use the `command/3` and `pipeline/3` APIs to execute Redis commands:

```elixir
{:ok, result} = LibRedis.command(standalone, ["GET", "mykey"])
```

The `command/3` function takes a LibRedis object, a Redis command as a list of strings, and an optional timeout in milliseconds. It returns a tuple with the status of the command execution and the result.

```elixir
{:ok, result} = LibRedis.pipeline(standalone, [
  ["SET", "mykey", "value1"],
  ["GET", "mykey"]
])
```

The `pipeline/3` function takes a LibRedis object and a list of Redis commands, where each command is represented as a list of strings. It returns a tuple with the status of the pipeline execution and a list of results.

### Redis Cluster

To use LibRedis with Redis cluster, first create a cluster using the `LibRedis.Cluster` module:

```elixir
cluster_options = [
  name: :redis,
  mode: :cluster,
  url: "redis://localhost:6381,redis://localhost:6382,redis://localhost:6383,redis://localhost:6384,redis://localhost:6385",
  password: "123456",
  pool_size: 5
]

cluster = LibRedis.new(cluster_options)
```

Then, add the `LibRedis` application to your supervision tree:

```elixir
children = [
  {LibRedis, redis: cluster}
]
```

The `cluster_options` parameter is a keyword list that contains the connection options for Redis cluster. 

Once you have a cluster, you can use the `command/3` and `pipeline/3` APIs to execute Redis commands:

```elixir
{:ok, result} = LibRedis.command(cluster, ["GET", "mykey"])
```

The `command/3` function takes a cluster object, a Redis command as a list of strings, and an optional timeout in milliseconds. It returns a tuple with the status of the command execution and the result.

```elixir
{:ok, result} = LibRedis.pipeline(cluster, [
  ["SET", "mykey", "value1"],
  ["GET", "mykey"]
])
```

The `pipeline/3` function takes a cluster object and a list of Redis commands, where each command is represented as a list of strings. It returns a tuple with the status of the pipeline execution and a list of results.


## Test
```
Cover compiling modules ...
............................
Finished in 3.3 seconds (0.00s async, 3.3s sync)
28 tests, 0 failures

Randomized with seed 28971

Generating cover results ...

Percentage | Module
-----------|--------------------------
    68.75% | LibRedis.Pool
    76.47% | LibRedis.SlotFinder
    80.00% | LibRedis.Cluster
    86.67% | LibRedis.ClientStore.Default
    96.43% | LibRedis
   100.00% | LibRedis.Client
   100.00% | LibRedis.ClientStore
   100.00% | LibRedis.SlotStore
   100.00% | LibRedis.SlotStore.Default
   100.00% | LibRedis.Standalone
   100.00% | LibRedis.Typespecs
-----------|--------------------------
    82.93% | Total

Coverage test failed, threshold not met:

    Coverage:   82.93%
    Threshold:  90.00%
```

## License

LibRedis is released under the [MIT License](https://opensource.org/licenses/MIT).