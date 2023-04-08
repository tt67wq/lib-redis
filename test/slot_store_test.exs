defmodule LibRedisTest.SlotStoreTest do
  use ExUnit.Case

  alias LibRedis.SlotStore.Default

  setup do
    store = Default.new()
    start_supervised!({Default, store: store})
    %{store: store}
  end

  test "put_and_get", %{store: store} do
    assert :ok = Default.put(store, [%{start_slot: 0, end_slot: 1}])
    assert [%{start_slot: 0, end_slot: 1}] = Default.get(store)
  end
end
