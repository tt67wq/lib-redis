defmodule LibRedis.ClientStore do
  @moduledoc """
  redis client store, using registry to store {host, port} -> pid mapping
  """
  # types
  @type t :: %__MODULE__{
          name: GenServer.name()
        }
  @type v :: pid() | nil
  @type k :: {bitstring(), non_neg_integer()}
  @type opts :: keyword()

  defstruct [:name]

  @spec new(opts()) :: t()
  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :client_store)

    struct(__MODULE__, opts)
  end

  @spec get(t(), k()) :: v()
  def get(store, {host, port}) do
    Registry.lookup(store.name, {host, port})
    |> case do
      [] ->
        nil

      [{pid, _}] ->
        pid
    end
  end

  @spec random(t()) :: v()
  def random(store) do
    Registry.keys(store.name, self())
    |> Enum.random()
    |> case do
      nil ->
        nil

      {host, port} ->
        get(store, {host, port})
    end
  end

  def child_spec(opts) do
    store = Keyword.fetch!(opts, :store)
    %{id: {__MODULE__, store.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts) do
    {store, _opts} = Keyword.pop!(opts, :store)
    Registry.start_link(keys: :unique, name: store.name)
  end
end
