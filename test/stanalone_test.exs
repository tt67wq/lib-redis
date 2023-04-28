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

  test "sending a command with a non-default database", %{redis: redis} do
    assert {:ok, "OK"} = LibRedis.command(redis, ["SELECT", 1], [])
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "foo", "bar"], [])
    assert {:ok, "bar"} = LibRedis.command(redis, ["GET", "foo"], [])
  end

  test "sending a command with options", %{redis: redis} do
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "foo", "bar"], timeout: 1000)
    assert {:ok, "bar"} = LibRedis.command(redis, ["GET", "foo"], timeout: 1000)
  end

  test "sending a command with a large bulk string reply", %{redis: redis} do
    value = String.duplicate("x", 1_000_000)
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "large_value", value], [])
    assert {:ok, result} = LibRedis.command(redis, ["GET", "large_value"], [])
    assert result == value
  end

  test "sending an invalid command", %{redis: redis} do
    assert {:error, _reason} = LibRedis.command(redis, ["INVALID_COMMAND", "key", "value"])
  end

  test "sending a command with an integer reply", %{redis: redis} do
    LibRedis.command(redis, ["SET", "counter", "1"])
    {:ok, result} = LibRedis.command(redis, ["INCR", "counter"], [])
    assert result == 2
  end

  test "sending a command with a negative integer reply", %{redis: redis} do
    LibRedis.command(redis, ["SET", "counter", "0"])
    assert {:ok, -5} = LibRedis.command(redis, ["DECRBY", "counter", "5"], [])
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
