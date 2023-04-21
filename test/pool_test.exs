defmodule LibRedisTest.Pool do
  use ExUnit.Case

  alias LibRedis.Pool

  @name :test_redis
  @url "redis://:123456@localhost:6379"

  setup do
    pool = Pool.new(name: @name, url: @url)
    start_supervised!({Pool, pool: pool})
    {:ok, %{pool: pool}}
  end

  test "command", %{pool: pool} do
    assert {:ok, "OK"} = Pool.command(pool, ["SET", "foo", "bar"])
    assert {:ok, "bar"} = Pool.command(pool, ["GET", "foo"])
  end

  test "pipeline", %{pool: pool} do
    Pool.command(pool, ["SET", "counter", 0])

    assert {:ok, ["OK", "value2", 1, "1"]} =
             Pool.pipeline(pool, [
               ["SET", "key2", "value2"],
               ["GET", "key2"],
               ["INCR", "counter"],
               ["GET", "counter"]
             ])
  end
end
