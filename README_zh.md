<!-- MDOC !-->
# LibRedis

LibRedis是一个使用Elixir编写的Redis客户端。它本质上是[Redix](https://github.com/whatyouhide/redix)项目的封装，拥有连接池和Redis集群功能的额外支持。该客户端提供了两个主要的API：`command/3`和`pipeline/3`。


## NOTE:
**Cluster模式在生产环境慎重使用，尚未测试完整**


## 特性
- [x] 连接池
- [x] 单例模式
- [x] 集群模式

## Installation

要在你的Elixir项目中使用LibRedis，只需在你的`mix.exs`文件中将其添加为依赖项：


```elixir
defp deps do
  [
    {:lib_redis, github: "tt67wq/lib-redis"}
  ]
end
```

## Usage

### 单例模式

要以单例模式使用LibRedis，你需要设置为`:standalone`模式： 

```elixir
standalone_options = [
  name: :redis,
  mode: :standalone,
  url: "redis://:pwd@localhost:6379",
  pool_size: 5
]

standalone = LibRedis.new(standalone_options)
```

然后将`LibRedis`应用程序添加到你的supervision tree中：

```elixir
children = [
  {LibRedis, redis: standalone}
]
```

`options`参数是一个关键字列表，其中包含了Redis连接的选项。`pool_size`选项指定了连接池中连接的数量。通过强大的[nimble_pool](https://github.com/dashbitco/nimble_pool)模块，我们可以轻松地使用连接池管理Redis连接。

一旦你获得了一个LibRedis实例，你就可以使用`command/3`和`pipeline/3`API执行Redis命令：

```elixir
{:ok, result} = LibRedis.command(standalone, ["GET", "mykey"])
```

`command/3`函数接受一个LibRedis对象、一个Redis命令(以字符串list形式)，以及一个可选的超时时间(以毫秒为单位)。它将返回一个tuple，其中包含命令执行状态和结果。

```elixir
{:ok, result} = LibRedis.pipeline(standalone, [
  ["SET", "mykey", "value1"],
  ["GET", "mykey"]
])
```

`pipeline/3`函数接受一个LibRedis对象和一个Redis命令列表，其中每个命令都表示为字符串列表。它将返回一个tuple，其中包含pipeline执行的状态和结果列表。


### Redis Cluster

要使用集群模式，你需要设置为`:cluster`模式： 

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

然后将`LibRedis`应用程序添加到你的supervision tree中：

```elixir
children = [
  {LibRedis, redis: cluster}
]
```

`cluster_options`参数是一个关键字列表，其中包含了Redis集群的连接选项。

一旦你获得了一个Redis集群实例，你就可以使用`command/3`和`pipeline/3`API执行Redis命令：

```elixir
{:ok, result} = LibRedis.command(cluster, ["GET", "mykey"])
```

`command/3`函数接受一个Redis cluster对象、一个Redis命令(以字符串list的形式表示)和一个可选的超时时间(以毫秒为单位)。它将返回一个tuple，其中包含命令执行状态和结果。


```elixir
{:ok, result} = LibRedis.pipeline(cluster, [
  ["SET", "mykey", "value1"],
  ["GET", "mykey"]
])
```

`pipeline/3`函数接受一个Redis集群对象和一个Redis命令列表，其中每个命令都表示为字符串列表。它将返回一个tuple，其中包含pipeline执行的状态和结果列表。



## Test
为了运行单元测试，可在本地用docker启动redis服务，然后执行`mix test`命令。

redis服务的具体启动方式可参考[docker-compose](./docker-compose/run.md)文件。

#### 集群服务
```yaml

```
Cover compiling modules ...
............................
Finished in 3.3 seconds (0.00s async, 3.3s sync)
28 tests, 0 failures

Randomized with seed 28971

Generating cover results ...

| Percentage  | Module                       |
| ----------- | ---------------------------- |
| 68.75%      | LibRedis.Pool                |
| 76.47%      | LibRedis.SlotFinder          |
| 80.00%      | LibRedis.Cluster             |
| 86.67%      | LibRedis.ClientStore.Default |
| 96.43%      | LibRedis                     |
| 100.00%     | LibRedis.Client              |
| 100.00%     | LibRedis.ClientStore         |
| 100.00%     | LibRedis.SlotStore           |
| 100.00%     | LibRedis.SlotStore.Default   |
| 100.00%     | LibRedis.Standalone          |
| 100.00%     | LibRedis.Typespecs           |
| ----------- | --------------------------   |
| 82.93%      | Total                        |

Coverage test failed, threshold not met:

    Coverage:   82.93%
    Threshold:  90.00%
```

## License

LibRedis is released under the [MIT License](https://opensource.org/licenses/MIT).