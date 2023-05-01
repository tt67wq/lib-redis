<!-- MDOC !-->
## LibRedis.Pool

Wrap [redix](https://github.com/whatyouhide/redix) with [nimble_pool](https://github.com/dashbitco/nimble_pool)

### Usage

```
iex> pool = LibRedis.Pool.new(name: :redis_pool, pool_size: 5, url: "redis://:123456@localhost:6379")
iex> {:ok, _} = LibRedis.Pool.start_link(pool: pool)
iex> LibRedis.Pool.command(pool, ["SET", "foo", "bar"])
{:ok, "OK"}
iex> LibRedis.Pool.pipeline(pool, [["SET", "foo", "bar"], ["SET", "bar", "foo"]])
{:ok, ["OK", "OK"]]}
```