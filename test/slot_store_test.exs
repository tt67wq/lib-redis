defmodule LibRedisTest.SlotStoreTest do
  use ExUnit.Case

  alias LibRedis.SlotStore

  setup do
    store = SlotStore.new()
    start_supervised!({SlotStore, store: store})
    {:ok, %{store: store}}
  end

  test "put_and_get", %{store: store} do
    assert :ok = SlotStore.put(store, [%{start_slot: 0, end_slot: 1}])
    assert [%{start_slot: 0, end_slot: 1}] = SlotStore.get(store)
  end
end
