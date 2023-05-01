<!-- MDOC !-->
# LibRedis

LibRedis is a Redis client written in Elixir. It is essentially a wrapper around the Redix project, with added support for connection pooling and Redis cluster functionality. The client exposes two main APIs: `command/3` and `pipeline/3`.

## Installation

To use LibRedis in your Elixir project, simply add it as a dependency in your `mix.exs` file:

```elixir
defp deps do
  [
    {:lib_redis, "~> 1.0"}
  ]
end
```

Then, run `mix deps.get` to install the dependency.

## Usage

### Connection Pooling

To use LibRedis with connection pooling, first create a pool using the `LibRedis.Pool` module:

```elixir
pool_options = [
  host: "localhost",
  port: 6379,
  database: 0,
  size: 5
]

pool = LibRedis.Pool.new(pool_options)
```

The `pool_options` parameter is a keyword list that contains the connection options for Redis. The `size` option specifies the number of connections in the pool.

Once you have a pool, you can use the `command/3` and `pipeline/3` APIs to execute Redis commands:

```elixir
{:ok, result} = LibRedis.command(pool, ["GET", "mykey"])
```

The `command/3` function takes a pool object, a Redis command as a list of strings, and an optional timeout in milliseconds. It returns a tuple with the status of the command execution and the result.

```elixir
{:ok, result} = LibRedis.pipeline(pool, [
  ["SET", "mykey", "value1"],
  ["GET", "mykey"]
])
```

The `pipeline/3` function takes a pool object and a list of Redis commands, where each command is represented as a list of strings. It returns a tuple with the status of the pipeline execution and a list of results.

### Redis Cluster

To use LibRedis with Redis cluster, first create a cluster using the `LibRedis.Cluster` module:

```elixir
cluster_options = [
  nodes: [
    "redis://localhost:7000",
    "redis://localhost:7001",
    "redis://localhost:7002"
  ]
]

cluster = LibRedis.Cluster.new(cluster_options)
```

The `cluster_options` parameter is a keyword list that contains the connection options for Redis cluster. The `nodes` option specifies a list of Redis nodes in the cluster.

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