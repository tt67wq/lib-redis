defmodule LibRedis.SlotStore do
  @moduledoc """
  used to store slot topology
  """

  alias LibRedis.Typespecs

  # types
  @opaque node_info :: Typespecs.node_info()
  @opaque slot :: Typespecs.slot()
  @opaque opts :: keyword()
  @type t :: %__MODULE__{
          name: GenServer.name()
        }

  defstruct [:name]

  @doc """
  new storage
  the only argument is `:name`, which is the name of the storage

  ## Examples

      iex> LibRedis.SlotStore.Default.new(name: :slot_agent)
  """
  @spec new(opts()) :: t()
  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :slot_agent)

    struct(__MODULE__, opts)
  end

  @doc """
  get slots layer

  ## Examples

      iex> s = LibRedis.SlotStore.Default.new()
      iex> LibRedis.SlotStore.Default.get(s)
  """
  @spec get(t()) :: [slot()]
  def get(store) do
    Agent.get(store.name, & &1)
  end

  @doc """
  srore slots layer

  ## Examples

      iex> s = LibRedis.SlotStore.Default.new()
      iex> LibRedis.SlotStore.Default.put(s, [%{start_slot: 0, end_slot: 1}])
      :ok
  """
  @spec put(t(), [slot()]) :: :ok
  def put(store, slots) do
    Agent.update(store.name, fn _ -> slots end)
  end

  def child_spec(opts) do
    store = Keyword.fetch!(opts, :store)
    %{id: {__MODULE__, store.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  def start_link(opts) do
    {store, _opts} = Keyword.pop!(opts, :store)
    Agent.start_link(fn -> %{} end, name: store.name)
  end
end
