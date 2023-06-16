defmodule LibRedis.Utils do
  @moduledoc """
  some tools
  """

  @spec debug(any()) :: any()
  def debug(msg), do: tap(msg, &IO.inspect(&1))
end
