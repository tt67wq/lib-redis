<!-- MDOC !-->
# LibRedis

LibRedis is an eloquently crafted Redis client implemented in Elixir. It serves as a remarkable encapsulation of the [Redix](https://github.com/whatyouhide/redix) project, while additionally incorporating connection pooling and Redis cluster capabilities. Within this client, two primary interfaces are exposed, namely `command/3` and `pipeline/3`.

Please refer to the detailed project documentation: [hexdocs](https://hexdocs.pm/lib_redis/0.1.1/LibRedis.html)

## WARNING:
**The deployment of the Cluster mode in a production environment necessitates meticulous deliberation and vigilance, as it is still undergoing comprehensive and stringent testing.**

## Features
- [x] Connection pooling
- [x] Standalone mode
- [x] Cluster mode

## Installation

To use LibRedis in your Elixir project, simply add it as a dependency in your `mix.exs` file:

```elixir
defp deps do
  [
    {:lib_redis, "~> 0.1.1"}
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

## Design

### Connection Pooling
I leverage [nimble_pool](https://github.com/dashbitco/nimble_pool) to encapsulate Redix connections and administer them within a pool. Every time a command or pipeline operation is executed, a connection is acquired from the pool and subsequently returned upon completion of the operation.

### Standalone Mode
In standalone mode, the client maintains a solitary connection pool to a singular Redis instance. The client will seamlessly reestablish connection with the Redis instance in the event of any disruption.

### Cluster Mode
Cluster mode presents a significantly more intricate setup compared to standalone mode. Within this mode, the client executes the `CLUSTER SLOTS` command to obtain the cluster's topology. The client periodically retrieves this topology, typically every 10 seconds (though it can be adjusted), and stores it locally in the form of a cache (known as an Agent).

This cache facilitates the client's management of node addresses and their corresponding connections. If an address is not found within the cache, the client promptly establishes a new connection and stores it accordingly.

The client processes a single command by first identifying the node to which the command should be sent based on the command's key. It then locates the corresponding connection from the cache and executes the command on the connection.

Pipeline operation is far more complex than command operation. 
- first, client will group commands in pipelines by it's key;
- then, client will iterate the grouped pipelines and execute them in parallel;
- finnal, client will merge the results of the pipelines and return them to the caller.

Client will automatically retry the command if the command fails due to a connection error. If the command fails due to a Redis error, the client will return the error to the caller. If the command fails with a `Moved` error, means cluster topology has changed, the client will update the cluster topology and retry the command.

## Test
To run unit tests, you can start a Redis service using Docker locally and then execute the `mix test` command.

The specific way to start the Redis service can be referred to in the run.md file under the docker-compose directory.

```
Compiling 8 files (.ex)
Generated lib_redis app
Cover compiling modules ...
Finished in 3.3 seconds (0.00s async, 3.3s sync)
32 tests, 0 failures

Randomized with seed 498986

Generating cover results ...

Percentage | Module
-----------|--------------------------
     0.00% | LibRedis.Utils
    50.00% | LibRedis.Error
    50.00% | LibRedis.Standalone
    71.88% | LibRedis.Pool
    76.47% | LibRedis.SlotFinder
    77.91% | LibRedis.Cluster
    93.75% | LibRedis.ClientStore
    96.15% | LibRedis
   100.00% | LibRedis.Client
   100.00% | LibRedis.SlotStore
   100.00% | LibRedis.Typespecs
-----------|--------------------------
    80.71% | Total

Coverage test failed, threshold not met:

    Coverage:   80.71%
    Threshold:  90.00%

Generated HTML coverage results in "cover" directory
```

## License

LibRedis is released under the [MIT License](https://opensource.org/licenses/MIT).