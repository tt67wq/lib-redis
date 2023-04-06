defmodule LibRedisTest.Pool do
  use ExUnit.Case

  alias LibRedis.Pool

  @url "redis://:123456@localhost:6379"

  setup do
    {:ok, pid} = Pool.start_link(name: PoolTest, url: @url)
    {:ok, pid: pid}
  end

  test "set/get", %{pid: pid} do
    assert {:ok, "OK"} = Pool.command(pid, ["SET", "foo", "bar"])
    assert {:ok, "bar"} = Pool.command(pid, ["GET", "foo"])
  end
end
