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

    start_supervised!({LibRedis, redis: redis})
    {:ok, %{redis: redis}}
  end

  test "command", %{redis: redis} do
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "foo", "bar"])
    assert {:ok, "bar"} = LibRedis.command(redis, ["GET", "foo"])
  end

  test "sending a command with options", %{redis: redis} do
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "foo", "bar"], timeout: 1000)
    assert {:ok, "bar"} = LibRedis.command(redis, ["GET", "foo"], timeout: 1000)
  end

  test "sending an invalid command", %{redis: redis} do
    assert {:error, _reason} = LibRedis.command(redis, ["INVALID_COMMAND", "key", "value"])
  end

  test "sending an invalid pipeline", %{redis: redis} do
    assert {:ok, [%Redix.Error{}, "OK"]} =
             LibRedis.pipeline(redis, [
               ["INVALID_COMMAND", "key", "value"],
               ["SET", "key1", "value1"]
             ])
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

  test "pipeline incr and decr", %{redis: redis} do
    LibRedis.command(redis, ["SET", "counter", 0])

    assert {:ok, [1, 0, 1]} =
             LibRedis.pipeline(redis, [
               ["INCR", "counter"],
               ["DECR", "counter"],
               ["INCR", "counter"]
             ])
  end

  test "pipeline hset and hget", %{redis: redis} do
    assert {:ok, [0, "John"]} =
             LibRedis.pipeline(redis, [
               ["HSET", "user1", "name", "John"],
               ["HGET", "user1", "name"]
             ])
  end

  test "multiple successful commands", %{redis: redis} do
    result =
      LibRedis.pipeline(redis, [
        ["SET", "key1", "value1"],
        ["SET", "key2", "value2"],
        ["SET", "key3", "value3"]
      ])

    assert result == {:ok, ["OK", "OK", "OK"]}
  end

  test "one command fail", %{redis: redis} do
    assert {:ok, ["OK", %Redix.Error{}, "OK"]} =
             LibRedis.pipeline(redis, [
               ["SET", "key1", "value1"],
               ["SETXX", "key2", "value2"],
               ["SET", "key3", "value3"]
             ])
  end

  test "multiple operations on same key in pipeline", %{redis: redis} do
    assert {:ok, ["OK", "value", "OK"]} =
             LibRedis.pipeline(redis, [
               ["SET", "key", "value"],
               ["GET", "key"],
               ["SET", "key", "value"]
             ])
  end

  test "mix pipeline and non-pipeline commands", %{redis: redis} do
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "key", "value"])
    assert {:ok, "OK"} = LibRedis.command(redis, ["SET", "counter", "2"])

    assert {:ok, [3, "OK", "value"]} =
             LibRedis.pipeline(redis, [["INCR", "counter"], ["SET", "key22", "ok"], ["GET", "key"]])
  end

  test "large pipeline", %{redis: redis} do
    cmds = for i <- 1..10000, do: ["SET", "key#{i}", "value#{i}"]
    assert {:ok, results} = LibRedis.pipeline(redis, cmds)
    assert Enum.all?(results, fn res -> res == "OK" end)
  end
end
