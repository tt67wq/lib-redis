defmodule LibRedis do
  @external_resource "docs/lib_redis.md"
  @moduledoc "docs/lib_redis.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias LibRedis.{Standalone, Cluster}
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
      Cluster.new(
        name: redis.name,
        urls: redis.url |> url_to_cluster_urls(),
        password: redis.password,
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

  defp url_to_cluster_urls(url) do
    url
    |> String.split(",")
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
          password: bitstring(),
          pool_size: non_neg_integer(),
          refresh_interval_ms: non_neg_integer(),
          client_store: module(),
          slot_store: module()
        }

  @type node_info :: %{ip: bitstring(), port: non_neg_integer()}

  @type slot_info :: %{
          start_slot: non_neg_integer(),
          end_slot: non_neg_integer(),
          master: node_info(),
          replicas: [node_info()]
        }

  @url_regex ~r/^redis:\/\/\w+:\d+$/
  @enforce_keys ~w(name urls password pool_size refresh_interval_ms client_store slot_store)a

  defstruct @enforce_keys

  @impl Client
  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :cluster)
      |> Keyword.put_new(:urls, ["redis://localhost:6379"])
      |> Keyword.put_new(:password, "")
      |> Keyword.put_new(:pool_size, 10)
      |> Keyword.put_new(:refresh_interval_ms, 10_000)
      |> Keyword.put_new(:client_store, LibRedis.ClientStore.Default)
      |> Keyword.put_new(:slot_store, LibRedis.SlotStore.Default)

    opts[:urls]
    |> Enum.map(fn url ->
      if not valid_redis_url?(url) do
        raise ArgumentError, "invalid url: #{url}"
      end
    end)

    struct(__MODULE__, opts)
  end

  defp valid_redis_url?(url), do: Regex.match?(@url_regex, url)

  def child_spec(opts) do
    cluster = Keyword.fetch!(opts, :cluster)
    %{id: {__MODULE__, cluster.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {cluster, _opts} = Keyword.pop!(opts, :cluster)
    GenServer.start(__MODULE__, cluster, name: cluster.name)
  end

  @impl Client
  def command(client, command, opts \\ []) do
    GenServer.call(client.name, {:command, command, opts})
  end

  @impl Client
  def pipeline(client, commands, opts \\ []) do
    GenServer.call(client.name, {:pipeline, commands, opts})
  end

  defp url_with_password(url, ""), do: url

  defp url_with_password(url, password) do
    prefix = String.slice(url, 0, 8)
    prefix <> ":" <> password <> "@" <> String.slice(url, 8..-1)
  end

  defp random_name() do
    :crypto.strong_rand_bytes(16)
    |> Base.encode64()
    |> String.to_atom()
  end

  defp parse_url(url) do
    [ip, port] =
      url
      |> String.slice(8..-1)
      |> String.split(":")

    {ip, String.to_integer(port)}
  end

  def init(cluster) do
    slot_store = cluster.slot_store.new()
    client_store = cluster.client_store.new()
    {:ok, _} = cluster.slot_store.start_link(store: slot_store)
    {:ok, _} = cluster.client_store.start_link(store: client_store)

    cluster.urls
    |> Enum.map(fn url ->
      {host, port} = parse_url(url)

      cluster.client_store.new(
        host: host,
        port: port,
        opts: [
          name: random_name(),
          pool_size: cluster.pool_size,
          url: url_with_password(url, cluster.password)
        ]
      )
    end)
    |> Enum.each(&LibRedis.ClientStore.get(&1))

    send(self(), :refresh)

    {:ok, %{cluster: cluster, client_store: client_store, slot_store: slot_store}}
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

  defp reload_slot_info(client_store) do
    client_store
    |> LibRedis.ClientStore.random()
    |> LibRedis.Standalone.command(["CLUSTER", "SLOTS"], [])
    |> case do
      {:ok, slot_info} -> slot_info
      {:error, _} -> []
    end
    |> parse_slot_info()
  end

  def handle_info(:refresh, %{client_store: cs, slot_store: ss} = state) do
    cs
    |> reload_slot_info()
    |> (fn x -> LibRedis.SlotStore.put(ss, x) end).()

    Process.send_after(self(), :refresh, 60_000)

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
        {:reply, {:ok, result}, state}

      {:error, %Redix.Error{message: msg}} when retries_left > 0 ->
        if String.starts_with?(msg, "MOVED") do
          send(self(), :refresh)
        end

        try_command(state, command, opts, retries_left - 1)

      {:error, _reason} when retries_left > 0 ->
        try_command(state, command, opts, retries_left - 1)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp try_pipeline(state, commands, opts, retries_left) do
    case do_pipeline(state, commands, opts) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      {:error, %Redix.Error{message: msg}} when retries_left > 0 ->
        if String.starts_with?(msg, "MOVED") do
          send(self(), :refresh)
        end

        try_pipeline(state, commands, opts, retries_left - 1)

      {:error, _reason} when retries_left > 0 ->
        try_pipeline(state, commands, opts, retries_left - 1)

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp do_command(
         %{cluster: cluster, slot_store: ss},
         [_, key | _] = command,
         opts
       ) do
    target = LibRedis.SlotFinder.hash_slot(key)

    ss
    |> LibRedis.SlotStore.get()
    |> Enum.find(fn x -> x.start_slot <= target and x.end_slot >= target end)
    |> case do
      nil ->
        {:error, "slot not found"}

      slot ->
        cluster.client_store.new(
          host: slot.master.ip,
          port: slot.master.port,
          opts: [
            name: random_name(),
            pool_size: cluster.pool_size,
            url:
              url_with_password(
                "redis://:#{cluster.password}@#{slot.master.ip}:#{slot.master.port}",
                ""
              )
          ]
        )
        |> LibRedis.ClientStore.get()
        |> LibRedis.Standalone.command(command, opts)
    end
  end

  defp group_commands([], _, acc), do: acc

  defp group_commands([command | t], %{slot_store: ss, cluster: cluster} = state, acc) do
    [_, key | _] = command
    target = LibRedis.SlotFinder.hash_slot(key)

    ss
    |> LibRedis.SlotStore.get()
    |> Enum.find(fn x -> x.start_slot <= target and x.end_slot >= target end)
    |> case do
      nil ->
        {:error, "slot not found"}

      slot ->
        cli =
          cluster.client_store.new(
            host: slot.master.ip,
            port: slot.master.port,
            opts: [
              name: random_name(),
              pool_size: cluster.pool_size,
              url:
                url_with_password(
                  "redis://:#{cluster.password}@#{slot.master.ip}:#{slot.master.port}",
                  ""
                )
            ]
          )
          |> LibRedis.ClientStore.get()

        group_commands(t, state, Map.update(acc, cli, [command], &(&1 ++ [command])))
    end
  end

  defp do_pipeline(state, commands, opts) do
    commands
    |> group_commands(state, %{})
    |> Map.to_list()
    |> Enum.reduce_while([], fn {client, commands}, acc ->
      LibRedis.Standalone.pipeline(client, commands, opts)
      |> case do
        {:ok, ret} -> {:cont, Enum.zip(commands, ret) ++ acc}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:error, _} = err ->
        err

      res ->
        x =
          commands
          |> Enum.map(fn command ->
            res
            |> Enum.find(fn {c, _} -> c == command end)
            |> elem(1)
          end)

        {:ok, x}
    end
  end
end
