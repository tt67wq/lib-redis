<!-- MDOC !-->
# LibRedis

LibRedis is a Redis client written in Elixir. It is essentially a wrapper around the [Redix](https://github.com/whatyouhide/redix) project, with added support for connection pooling and Redis cluster functionality. 
The client exposes two main APIs: `command/3` and `pipeline/3`.

## NOTE:
还没写好，别用先!!!!

Don't use it in production, it's not ready yet.

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

To use LibRedis in singleton mode, you have to starts with `:standalone` mode:

```elixir
standalone_options = [
  name: :redis,
  mode: :standalone,
  url: "redis://:pwd@localhost:6379",
  pool_size: 5
]

standalone = LibRedis.new(standalone_options)
```

Then, add the `:lib_redis` application to your supervision tree:

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

Then, add the `:lib_redis` application to your supervision tree:

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

## License

LibRedis is released under the [MIT License](https://opensource.org/licenses/MIT).