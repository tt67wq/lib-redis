defmodule LibRedis.ClientStore do
  @moduledoc """
  behaviour for redis client store
  """
  # types
  @type t :: struct()
  @type v :: LibRedis.Pool.t()
  @type opts :: keyword()

  @callback start_link(store: t()) :: GenServer.on_start()
  @callback new(opts()) :: t()
  @callback get(t()) :: v()
  @callback random(t()) :: v()

  @spec get(t()) :: v()
  def get(store), do: delegate(store, :get, [])

  @spec random(t()) :: v()
  def random(store), do: delegate(store, :random, [])

  defp delegate(%module{} = storage, func, args),
    do: apply(module, func, [storage | args])
end

defmodule LibRedis.ClientStore.Default do
  @moduledoc """
  Default ClientStore implementation using ETS
  """

  alias LibRedis.ClientStore

  @behaviour ClientStore

  # types
  @type t :: %__MODULE__{
          name: GenServer.name(),
          host: bitstring(),
          port: non_neg_integer(),
          opts: keyword()
        }

  @enforce_keys ~w(name host port opts)a

  defstruct @enforce_keys

  @impl ClientStore
  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :client_store)
      |> Keyword.put_new(:host, "localhost")
      |> Keyword.put_new(:port, 6379)
      |> Keyword.put_new(:opts, [])

    struct(__MODULE__, opts)
  end

  @impl ClientStore
  def get(store) do
    :ets.lookup(store.name, {store.host, store.port})
    |> case do
      [] ->
        store.opts
        |> LibRedis.Pool.new()
        |> tap(&LibRedis.Pool.start_link(pool: &1))
        |> tap(&:ets.insert(store.name, {{store.host, store.port}, &1}))

      [{_, cli}] ->
        cli
    end
  end

  @impl ClientStore
  def random(store), do: :ets.tab2list(store.name) |> Enum.random() |> elem(1)

  def child_spec(opts) do
    store = Keyword.fetch!(opts, :store)
    %{id: {__MODULE__, store.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @impl ClientStore
  def start_link(opts) do
    {store, _opts} = Keyword.pop!(opts, :store)
    Agent.start_link(fn -> :ets.new(store.name, [:set, :public, :named_table]) end)
  end
end
