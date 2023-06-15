defmodule LibRedis.Typespecs do
  @moduledoc """
  Some typespecs for LibRedis
  """

  @type name :: atom() | pid()
  @type url :: bitstring()
  @type password :: bitstring()
  @type on_start :: {:ok, pid()} | {:error, term()}
  @type command_t :: [binary() | bitstring()]
  @type node_info :: %{ip: bitstring(), port: non_neg_integer()}
  @type slot :: %{
          start_slot: non_neg_integer(),
          end_slot: non_neg_integer(),
          master: node_info(),
          replicas: [node_info()]
        }
end
