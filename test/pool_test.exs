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

  test "set/get", %{pool: pool} do
    assert {:ok, "OK"} = Pool.command(pool, ["SET", "foo", "bar"])
    assert {:ok, "bar"} = Pool.command(pool, ["GET", "foo"])
  end
end
