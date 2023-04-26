defmodule LibRedisTest.Cluster do
  use ExUnit.Case

  alias LibRedis

  setup do
    redis =
      LibRedis.new(
        name: :test_cluster,
        mode: :cluster,
        password: "123456",
        url:
          "redis://localhost:6381,redis://localhost:6382,redis://localhost:6383,redis://localhost:6384,redis://localhost:6385"
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
