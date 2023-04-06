defmodule LibRedis.SlotStore do
  @moduledoc """
  Behavior for slot store
  """

  # types
  @type t :: struct()
  @type node_info :: %{ip: bitstring(), port: non_neg_integer()}
  @type slot :: %{
          start_slot: non_neg_integer(),
          end_slot: non_neg_integer(),
          master: node_info(),
          replicas: [node_info()]
        }
  @type opts :: keyword()

  @callback new(opts()) :: t()
  @callback get(t()) :: [slot()]
  @callback put(t(), [slot()]) :: :ok | {:error, any()}

  def get(store), do: delegate(store, :get, [])

  def put(store, slots), do: delegate(store, :put, [slots])

  defp delegate(%module{} = storage, func, args),
    do: apply(module, func, [storage | args])
end
