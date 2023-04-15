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

  # [
  #   [
  #     5461,
  #     10922,
  #     ["172.22.0.2", 6382, "3c3532bc5c3b50824b38781f71b0cfd8adbc4a4e"],
  #     ["172.22.0.6", 6386, "126313c7fb36892a47f13dd1f99395a896ab6664"]
  #   ],
  #   [
  #     0,
  #     5460,
  #     ["172.22.0.11", 6381, "e379ca17f7ea227136b3d06313f399cdf34e0498"],
  #     ["172.22.0.5", 6385, "2bfe1190918a0913d4aa0a6521279ab453018c4f"]
  #   ],
  #   [
  #     10923,
  #     16383,
  #     ["172.22.0.3", 6383, "b5a765515764af6b8f3b02483b4c3c750f54e522"],
  #     ["172.22.0.4", 6384, "0e381c340df45e88751cbe562d34698f9047aa2c"]
  #   ]
  # ]
  test "get slot layer", %{conn: conn} do
    {:ok, ret} = Redix.command(conn, ["CLUSTER", "SLOTS"])
    IO.inspect(ret)
  end
end
