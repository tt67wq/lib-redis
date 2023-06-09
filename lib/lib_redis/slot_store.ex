defmodule LibRedis.SlotStore do
  @moduledoc """
  slot store behaviour, used to store slots layer
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

  @callback start_link(store: t()) :: GenServer.on_start()
  @callback new(opts()) :: t()
  @callback get(t()) :: [slot()]
  @callback put(t(), [slot()]) :: :ok | {:error, any()}

  def get(store), do: delegate(store, :get, [])

  def put(store, slots), do: delegate(store, :put, [slots])

  defp delegate(%module{} = storage, func, args),
    do: apply(module, func, [storage | args])
end

defmodule LibRedis.SlotStore.Default do
  @moduledoc """
  Default SlotStore implementation using Agent
  """

  alias LibRedis.SlotStore

  @behaviour SlotStore

  # types
  @type t :: %__MODULE__{
          name: GenServer.name()
        }

  @enforce_keys ~w(name)a

  defstruct @enforce_keys

  @doc """
  new storage
  the only argument is `:name`, which is the name of the storage

  ## Examples

      iex> LibRedis.SlotStore.Default.new(name: :slot_agent)
  """
  @impl SlotStore
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
  @impl SlotStore
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
  @impl SlotStore
  def put(store, slots) do
    Agent.update(store.name, fn _ -> slots end)
  end

  def child_spec(opts) do
    store = Keyword.fetch!(opts, :store)
    %{id: {__MODULE__, store.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @impl SlotStore
  def start_link(opts) do
    {store, _opts} = Keyword.pop!(opts, :store)
    Agent.start_link(fn -> %{} end, name: store.name)
  end
end
