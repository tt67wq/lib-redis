defmodule LibRedisTest.Standalone do
  use ExUnit.Case

  alias LibRedis

  setup do
    redis =
      LibRedis.new(
        name: :test_standalone,
        mode: :standalone,
        url: "redis://:123456@localhost:6379"
      )

    start_supervised({LibRedis, redis: redis})
    {:ok, %{redis: redis}}
  end

  test "command", %{redis: redis} do
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "foo", "bar"])
    assert {:ok, "bar"} = LibRedis.command(redis, ["GET", "foo"])
  end

  test "pipeline", %{redis: redis} do
    LibRedis.command(redis, ["SET", "counter", 0])

    assert {:ok, ["OK", "value2", 1, "1"]} =
             LibRedis.pipeline(redis, [
               ["SET", "key2", "value2"],
               ["GET", "key2"],
               ["INCR", "counter"],
               ["GET", "counter"]
             ])
  end
end
