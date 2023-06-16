defmodule LibRedisTest.ClientStoreTest do
  use ExUnit.Case

  alias LibRedis.ClientStore

  setup do
    store = ClientStore.new()
    start_supervised!({ClientStore, store: store})
    {:ok, %{store: store}}
  end

  test "get nil", %{store: store} do
    assert is_nil(ClientStore.get(store, {"localhost", 6379}))
  end

  test "register a pool", %{store: store} do
    [
      name: {:via, Registry, {store.name, {"localhost", 6379}}},
      pool_size: 2,
      url: "redis://:123456@localhost:6379"
    ]
    |> LibRedis.Pool.new()
    |> then(&LibRedis.Pool.start_link(pool: &1))

    assert not is_nil(ClientStore.get(store, {"localhost", 6379}))

    store
    |> ClientStore.get({"localhost", 6379})
    |> LibRedis.Pool.command(["PING"])
    |> then(&assert {:ok, "PONG"} == &1)
  end

  test "random", %{store: store} do
    [
      name: {:via, Registry, {store.name, {"localhost", 6379}}},
      pool_size: 2,
      url: "redis://:123456@localhost:6379"
    ]
    |> LibRedis.Pool.new()
    |> then(&LibRedis.Pool.start_link(pool: &1))

    assert not is_nil(ClientStore.get(store, {"localhost", 6379}))

    store
    |> ClientStore.random()
    |> LibRedis.Pool.command(["PING"])
    |> then(&assert {:ok, "PONG"} == &1)
  end
end
