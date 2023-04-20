defmodule LibRedis do
  @moduledoc """
  """
  alias LibRedis.Standalone
  # types
  @type t :: %__MODULE__{
          name: GenServer.name(),
          mode: :cluster | :standalone,
          url: bitstring(),
          password: bitstring(),
          pool_size: non_neg_integer(),
          client: Client.client()
        }

  @enforce_keys ~w(name mode url password pool_size client)a

  defstruct @enforce_keys

  defmodule Client do
    @type client :: term()
    @type command_t :: [binary() | bitstring()]

    @callback new(keyword()) :: client()
    @callback command(client(), command_t(), keyword()) :: {:ok, term()} | {:error, term()}
    @callback pipeline(client(), [command_t()], keyword()) :: {:ok, term()} | {:error, term()}

    def command(client, command, opts), do: delegate(client, :command, [command, opts])
    def pipeline(client, commands, opts), do: delegate(client, :pipeline, [commands, opts])

    defp delegate(%module{} = client, func, args),
      do: apply(module, func, [client | args])
  end

  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :redis)
      |> Keyword.put_new(:mode, :standalone)
      |> Keyword.put_new(:url, "redis://:123456@localhost:6379")
      |> Keyword.put_new(:password, "")
      |> Keyword.put_new(:pool_size, 10)

    __MODULE__
    |> struct(opts)
    |> with_client()
  end

  defp with_client(%__MODULE__{mode: :standalone} = redis) do
    client =
      Standalone.new(
        name: redis.name,
        url: redis.url,
        pool_size: redis.pool_size
      )

    %{redis | client: client}
  end

  defp with_client(%__MODULE__{mode: :cluster} = redis) do
    client =
      LibRedis.Cluster.new(
        name: redis.name,
        urls: url_to_cluster_urls(redis.url, redis.password),
        pool_size: redis.pool_size
      )

    %{redis | client: client}
  end

  def command(redis, command, opts \\ []) do
    Client.command(redis.client, command, opts)
  end

  def pipeline(redis, commands, opts \\ []) do
    Client.pipeline(redis.client, commands, opts)
  end

  def child_spec(opts) do
    redis = Keyword.fetch!(opts, :redis)
    %{id: {__MODULE__, redis.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {redis, _opts} = Keyword.pop!(opts, :redis)

    case redis.mode do
      :standalone ->
        LibRedis.Standalone.start_link(pool: redis.client)

      :cluster ->
        LibRedis.Cluster.start_link(cluster: redis.client)
    end
  end

  defp url_to_cluster_urls(url, "") do
    url
    |> String.split(",")
  end

  defp url_to_cluster_urls(url, password) do
    url
    |> String.split(",")
    |> Enum.map(fn url ->
      url
      |> String.replace("redis://", "redis://:" <> password <> "@")
    end)
  end
end

defmodule LibRedis.Standalone do
  @moduledoc """
  standalone redis client
  """

  alias LibRedis.{Client, Pool}

  @behaviour Client

  @impl Client
  defdelegate new(opts), to: Pool

  @impl Client
  defdelegate command(cli, command, opts), to: Pool

  @impl Client
  defdelegate pipeline(cli, commands, opts), to: Pool

  defdelegate start_link(opts), to: Pool
end

defmodule LibRedis.Cluster do
  @moduledoc """
  cluster redis client
  """

  alias LibRedis.{Client}

  @behaviour Client

  # types
  @type t :: %__MODULE__{
          name: GenServer.name(),
          urls: [bitstring()],
          pool_size: non_neg_integer()
        }

  @type node_info :: %{ip: bitstring(), port: non_neg_integer()}

  @type slot_info :: %{
          start_slot: non_neg_integer(),
          end_slot: non_neg_integer(),
          master: node_info(),
          replicas: [node_info()]
        }

  @enforce_keys ~w(name urls pool_size refresh_interval_ms)a

  defstruct @enforce_keys

  defmodule State do
    @moduledoc """
    state of cluster's genserver
    """

    @type t :: %__MODULE__{}

    @enforce_keys ~w(clients store)a

    defstruct @enforce_keys

    def new(opts \\ []) do
      opts =
        opts
        |> Keyword.put_new(:clients, %{})
        |> Keyword.put_new(:store, LibRedis.SlotStore.Default.new())

      struct(__MODULE__, opts)
    end
  end

  @impl Client
  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :cluster)
      |> Keyword.put_new(:urls, ["redis://:123456@localhost:6379"])
      |> Keyword.put_new(:pool_size, 10)
      |> Keyword.put_new(:refresh_interval_ms, 10_000)

    struct(__MODULE__, opts)
  end

  def child_spec(opts) do
    cluster = Keyword.fetch!(opts, :cluster)
    %{id: {__MODULE__, cluster.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {cluster, _opts} = Keyword.pop!(opts, :cluster)

    case cluster.urls do
      [url] ->
        LibRedis.Standalone.start_link(
          pool:
            LibRedis.Standalone.new(name: cluster.name, url: url, pool_size: cluster.pool_size)
        )

      _ ->
        GenServer.start(__MODULE__, cluster)
    end
  end

  @impl Client
  def command(client, command, opts \\ []) do
    GenServer.call(client.name, {:command, command, opts})
  end

  @impl Client
  def pipeline(client, commands, opts \\ []) do
    GenServer.call(client.name, {:pipeline, commands, opts})
  end

  # "redis://:123456@localhost:6379" => "localhost:6379"
  # "redis://localhost:6379" => "localhost:6379"
  defp get_host_from_url(url) do
    String.contains?(url, "@")
    |> if do
      String.split(url, "@")
      |> List.last()
    else
      String.slice(url, 8..-1)
    end
  end

  def init(cluster) do
    clients =
      cluster.urls
      |> Enum.with_index()
      |> Enum.map(fn {url, idx} ->
        {get_host_from_url(url),
         LibRedis.Standalone.new(
           name: :"#{cluster.name}-#{idx}",
           url: url,
           pool_size: cluster.pool_size
         )}
      end)
      |> Enum.reduce(%{}, fn {host, pool}, acc ->
        Map.put_new(acc, host, LibRedis.Standalone.start_link(pool: pool))
      end)

    Process.send_after(self(), :refresh, cluster.refresh_interval_ms)

    {:ok, State.new(clients: clients)}
  end

  # Response Format:
  # - Start slot range
  # - End slot range
  # - Master for slot range represented as nested IP/Port array
  # - First replica of master for slot range
  # - Second replica
  # ...continues until all replicas for this master are returned.
  # Ref - https://redis.io/commands/cluster-slots#nested-result-array
  @spec parse_slot_info(any) :: [slot_info()]
  defp parse_slot_info(slot_info) do
    Enum.map(slot_info, fn [start_slot, end_slot, master | replicas] ->
      %{
        start_slot: start_slot,
        end_slot: end_slot,
        master: parse_node_info(master),
        replicas: Enum.map(replicas, &parse_node_info/1)
      }
    end)
  end

  defp parse_node_info([node_ip, node_port, _node_id | _] = _node) do
    %{
      ip: node_ip,
      port: node_port
    }
  end

  @spec reload_slot_info(State.t()) :: [slot_info()]
  defp reload_slot_info(state) do
    state.clients
    |> Map.values()
    |> Enum.random()
    |> LibRedis.Standalone.command(["CLUSTER", "SLOTS"], [])
    |> parse_slot_info()
  end

  @spec get_slot_info(State.t()) :: [slot_info()]
  defp get_slot_info(state) do
    LibRedis.SlotStore.get(state.store)
  end

  def handle_info(:refresh, state) do
    state
    |> reload_slot_info()
    |> (fn x -> LibRedis.SlotStore.put(state.store, x) end).()

    Process.send_after(self(), :refresh, 10_000)

    {:noreply, state}
  end

  def handle_call({:command, command, opts}, _from, state) do
    try_command(state, command, opts, 3)
  end

  def handle_call({:pipeline, commands, opts}, _from, state) do
    try_pipeline(state, commands, opts, 3)
  end

  defp try_command(state, command, opts, retries_left) do
    case do_command(state, command, opts) do
      {:ok, result} ->
        {:reply, result, state}

      {:error, _reason} when retries_left > 0 ->
        try_command(state, command, opts, retries_left - 1)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp try_pipeline(state, commands, opts, retries_left) do
    case do_pipeline(state, commands, opts) do
      {:ok, result} ->
        {:reply, result, state}

      {:error, _reason} when retries_left > 0 ->
        try_pipeline(state, commands, opts, retries_left - 1)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_command(state, [_, key | _] = command, opts) do
    target = LibRedis.SlotFinder.hash_slot(key)

    state
    |> get_slot_info()
    |> Enum.find(fn x -> x.start_slot <= target and x.end_slot >= target end)
    |> case do
      nil ->
        {:error, "slot not found"}

      slot ->
        client = state.clients[slot.master.ip <> ":" <> Integer.to_string(slot.master.port)]
        LibRedis.Standalone.command(client, command, opts)
    end
  end

  # client => [command]
  defp group_commands([], _, acc), do: acc

  defp group_commands([command | t], state, acc) do
    [_, key | _] = command
    target = LibRedis.SlotFinder.hash_slot(key)

    state
    |> get_slot_info()
    |> Enum.find(fn x -> x.start_slot <= target and x.end_slot >= target end)
    |> case do
      nil ->
        {:error, "slot not found"}

      slot ->
        client = state.clients[slot.master.ip <> ":" <> Integer.to_string(slot.master.port)]
        group_commands(t, state, Map.update(acc, client, [command], &(&1 ++ [command])))
    end
  end

  defp do_pipeline(state, commands, opts) do
    commands
    |> group_commands(state, %{})
    |> Enum.reduce_while([], fn {client, commands}, acc ->
      LibRedis.Standalone.pipeline(client, commands, opts)
      |> case do
        {:ok, ret} -> {:cont, acc ++ ret}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> (fn
          {:error, _} = err -> err
          x -> {:ok, x}
        end).()
  end
end
