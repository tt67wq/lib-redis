defmodule LibRedis.SlotFinderTest do
  use ExUnit.Case

  alias LibRedis.SlotFinder

  @url "redis://:123456@localhost:6381"

  setup do
    {:ok, conn} = Redix.start_link(@url)
    {:ok, %{conn: conn}}
  end

  defp random_string(length) do
    bytes = :crypto.strong_rand_bytes(length)
    Base.url_encode64(bytes)
  end

  test "slot hash", %{conn: conn} do
    1..10
    |> Enum.each(fn i ->
      key = "foo#{random_string(i)}"
      {:ok, ret} = Redix.command(conn, ["CLUSTER", "KEYSLOT", key])
      assert ret == SlotFinder.hash_slot(key)
    end)
  end
end
