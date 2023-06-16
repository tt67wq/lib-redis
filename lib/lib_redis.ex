defmodule LibRedis.Client do
  @moduledoc """
  Redis client behaviour, there are 2 implementations of this behaviour:
  - LibRedis.Standalone
  - LibRedis.Cluster
  """
  alias LibRedis.{Typespecs, Error}

  @type t :: struct()
  @opaque command_t :: Typespecs.command_t()
  @type resp_t :: {:ok, term()} | Error.t()

  @callback new(keyword()) :: t()
  @callback start_link(keyword()) :: Typespecs.on_start()
  @callback command(t(), command_t(), keyword()) :: resp_t()
  @callback pipeline(t(), [command_t()], keyword()) :: resp_t()

  @spec command(t(), command_t(), keyword()) :: resp_t()
  def command(client, command, opts), do: delegate(client, :command, [command, opts])

  @spec pipeline(t(), [command_t()], keyword()) :: resp_t()
  def pipeline(client, commands, opts), do: delegate(client, :pipeline, [commands, opts])

  defp delegate(%module{} = client, func, args),
    do: apply(module, func, [client | args])
end

defmodule LibRedis do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias LibRedis.{Standalone, Cluster, Typespecs, Client}

  @client_options_schema [
    name: [
      type: :atom,
      default: :redis,
      doc: "The name of the redis client"
    ],
    mode: [
      type: {:in, [:standalone, :cluster]},
      default: :standalone,
      doc: "The mode of the redis client, :standalone or :cluster"
    ],
    url: [
      type: :string,
      required: true,
      doc: "The url of the redis server, like redis://:123456@localhost:6379"
    ],
    password: [
      type: :string,
      default: "",
      doc: "The password of the redis server, this option is useful in cluster mode"
    ],
    pool_size: [
      type: :non_neg_integer,
      default: 10,
      doc: "The pool size of the redis client's pool"
    ]
  ]
  @type options() :: [unquote(NimbleOptions.option_typespec(@client_options_schema))]
  # types
  @type t :: %__MODULE__{
          name: Typespecs.name(),
          mode: :cluster | :standalone,
          url: Typespecs.url(),
          password: Typespecs.password(),
          pool_size: non_neg_integer(),
          client: Client.t(),
          client_store_module: module(),
          slot_store_module: module()
        }

  @enforce_keys ~w(name mode url password pool_size client client_store_module slot_store_module)a

  defstruct @enforce_keys

  @doc """
  create a new redis client

  ## Options
  #{NimbleOptions.docs(@client_options_schema)}

  ## Examples

      iex> standalone_options = [
        name: :redis,
        mode: :standalone,
        url: "redis://:pwd@localhost:6379",
        pool_size: 5
      ]
      iex> LibRedis.new(standalone_options)
  """
  @spec new(options()) :: t()
  def new(opts \\ []) do
    opts = opts |> NimbleOptions.validate!(@client_options_schema)

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

  @doc """
  execute a redis command

  ## Examples

      iex> LibRedis.command(redis, ["SET", "key", "value"])
      {:ok, "OK"}
  """
  @spec command(t(), Client.command_t(), keyword()) :: Client.resp_t()
  def command(redis, command, opts \\ []) do
    Client.command(redis.client, command, opts)
  end

  @doc """
  execute a redis pipeline

  ## Examples

      iex> LibRedis.pipeline(redis, [["SET", "key", "value"], ["GET", "key"]])
      {:ok, ["OK", "value"]}
  """
  @spec pipeline(t(), [Client.command_t()], keyword()) :: Client.resp_t()
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
  Standalone redis client is just a delegate to LibRedis.Pool
  """

  alias LibRedis.{Client, Pool}

  @behaviour Client

  @impl Client
  defdelegate new(opts), to: Pool

  @impl Client
  defdelegate command(cli, command, opts), to: Pool

  @impl Client
  defdelegate pipeline(cli, commands, opts), to: Pool

  @impl Client
  defdelegate start_link(opts), to: Pool
end

defmodule LibRedis.Cluster do
  @moduledoc """
  cluster redis client
  """

  alias LibRedis.{Client, Typespecs, Error}
  require Logger

  @behaviour Client

  # types
  @type t :: %__MODULE__{
          name: Typespecs.name(),
          urls: [Typespecs.url()],
          password: Typespecs.password(),
          pool_size: non_neg_integer(),
          refresh_interval_ms: non_neg_integer(),
          client_store: ClientStore.t(),
          slot_store: SlotStore.t()
        }

  @type node_info :: %{ip: bitstring(), port: non_neg_integer()}

  @type slot_info :: %{
          start_slot: non_neg_integer(),
          end_slot: non_neg_integer(),
          master: node_info(),
          replicas: [node_info()]
        }

  @opaque state :: %{cluster: t()}

  @url_regex ~r/^redis:\/\/\w+:\d+$/

  defstruct [
    :name,
    :urls,
    :password,
    :pool_size,
    :refresh_interval_ms,
    :client_store,
    :slot_store
  ]

  @impl Client
  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :cluster)
      |> Keyword.put_new(:password, "")
      |> Keyword.put_new(:pool_size, 10)
      |> Keyword.put_new(:refresh_interval_ms, 10_000)
      |> Keyword.put_new(:client_store, LibRedis.ClientStore.new())
      |> Keyword.put_new(:slot_store, LibRedis.SlotStore.new())

    opts[:urls]
    |> Enum.map(fn url ->
      if not valid_redis_url?(url) do
        raise ArgumentError, "invalid url: #{url}"
      end
    end)

    struct(__MODULE__, opts)
  end

  defp error_log(cmd, error),
    do: Logger.error(%{"mode" => "cluster", "error" => error, "cmd" => cmd})

  defp valid_redis_url?(url), do: Regex.match?(@url_regex, url)

  def child_spec(opts) do
    cluster = Keyword.fetch!(opts, :cluster)
    %{id: {__MODULE__, cluster.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @impl Client
  @spec start_link(cluster: t()) :: Typespecs.on_start()
  def start_link(cluster: cluster) do
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

  @spec parse_url(Typespecs.url()) :: {bitstring(), non_neg_integer()}
  defp parse_url(url) do
    [ip, port] =
      url
      |> String.slice(8..-1)
      |> String.split(":")

    {ip, String.to_integer(port)}
  end

  def init(cluster) do
    {:ok, _} = LibRedis.ClientStore.start_link(store: cluster.client_store)
    {:ok, _} = LibRedis.SlotStore.start_link(store: cluster.slot_store)

    cluster.urls
    |> Enum.map(fn url ->
      [
        name: {:via, Registry, {cluster.client_store.name, parse_url(url)}},
        pool_size: cluster.pool_size,
        url: url_with_password(url, cluster.password)
      ]
    end)
    |> Enum.map(&LibRedis.Pool.new(&1))
    |> Enum.map(&LibRedis.Pool.start_link(pool: &1))

    send(self(), :refresh)

    {:ok, %{cluster: cluster}}
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

  @spec refetch_slot_info(ClientStore.t()) :: [slot_info()]
  defp refetch_slot_info(client_store) do
    client_store
    |> LibRedis.ClientStore.random()
    |> LibRedis.Pool.command(["CLUSTER", "SLOTS"])
    |> case do
      {:ok, slot_info} -> slot_info
      {:error, _} -> []
    end
    |> parse_slot_info()
  end

  def handle_info(:refresh, %{cluster: cluster} = state) do
    cluster.client_store
    |> refetch_slot_info()
    |> (fn x -> LibRedis.SlotStore.put(cluster.slot_store, x) end).()

    Process.send_after(self(), :refresh, cluster.refresh_interval_ms)

    {:noreply, state}
  end

  def handle_call({:command, command, opts}, _from, state) do
    {:reply, try_command(state, command, opts, 3), state}
  end

  def handle_call({:pipeline, commands, opts}, _from, state) do
    res = try_pipeline(state, commands, opts)

    # resort by original order
    commands
    |> Enum.map(fn cmd ->
      {_, ret} =
        Enum.find(res, fn
          {^cmd, _} -> true
          _ -> false
        end)

      ret
    end)
    |> (fn x -> {:reply, {:ok, x}, state} end).()
  end

  @spec try_command(state(), Typespecs.command_t(), keyword(), non_neg_integer()) ::
          {:ok, any()} | {:error, any()}
  defp try_command(state, command, opts, retries_left) do
    case do_command(state, command, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, %Redix.Error{message: msg}} when retries_left > 0 ->
        if String.starts_with?(msg, "MOVED") do
          send(self(), :refresh)
        end

        try_command(state, command, opts, retries_left - 1)

      {:error, _reason} when retries_left > 0 ->
        try_command(state, command, opts, retries_left - 1)

      {:error, reason} ->
        error_log(command, reason)
        {:error, Error.new(inspect(reason))}
    end
  end

  @spec try_pipeline(state(), [Typespecs.command_t()], keyword()) ::
          [{Typespecs.command_t(), any()}] | {:error, any()}
  defp try_pipeline(state, commands, opts) do
    group_commands(commands, state, %{})
    |> Map.to_list()
    |> Enum.reduce_while([], fn {client, cmds}, acc ->
      do_pipeline(client, cmds, opts, 3)
      |> case do
        {:ok, res} ->
          {:cont, acc ++ res}

        {:error, :moved} ->
          res = try_pipeline(state, cmds, opts)
          {:cont, acc ++ res}

        err ->
          {:halt, err}
      end
    end)
    |> Enum.reverse()
  end

  @spec do_command(state(), Typespecs.command_t(), Keyword.t()) :: {:ok, term()} | {:error, any}
  defp do_command(
         %{cluster: cluster},
         [_, key | _] = command,
         opts
       ) do
    get_client_by_key(cluster, key)
    |> case do
      nil -> {:error, "slot not found"}
      client -> LibRedis.Pool.command(client, command, opts)
    end
  end

  @spec do_pipeline(
          LibRedis.Pool.t() | pid(),
          [Typespecs.command_t()],
          Keyword.t(),
          non_neg_integer()
        ) ::
          {:ok, [{Typespecs.command_t(), term()}]} | {:error, any}
  defp do_pipeline(client, commands, opts, retries_left) do
    case LibRedis.Pool.pipeline(client, commands, opts) do
      {:ok, result} ->
        {:ok, Enum.zip(commands, result)}

      {:error, %Redix.Error{message: msg}} when retries_left > 0 ->
        if String.starts_with?(msg, "MOVED") do
          send(self(), :refresh)
          {:error, :moved}
        else
          do_pipeline(client, commands, opts, retries_left - 1)
        end

      {:error, _reason} when retries_left > 0 ->
        do_pipeline(client, commands, opts, retries_left - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # group_commands takes a list of commands and groups them by slot.
  # returns a map of standalone-client -> command list
  @spec group_commands([Typespecs.command_t()], state(), map()) ::
          %{
            (LibRedis.Pool.t() | pid()) => [Typespecs.command_t()]
          }
          | {:error, any()}
  defp group_commands([], _, acc), do: acc

  defp group_commands([command | t], %{cluster: cluster} = state, acc) do
    [_, key | _] = command

    get_client_by_key(cluster, key)
    |> case do
      nil ->
        {:error, "slot not found"}

      cli ->
        group_commands(t, state, Map.update(acc, cli, [command], &(&1 ++ [command])))
    end
  end

  @spec load_client(t(), Typespecs.slot()) :: LibRedis.Pool.t() | pid()
  defp load_client(cluster, slot) do
    cluster.client_store
    |> LibRedis.ClientStore.get({slot.master.ip, slot.master.port})
    |> case do
      nil ->
        [
          name: {:via, Registry, {cluster.client_store.name, {slot.master.ip, slot.master.port}}},
          pool_size: cluster.pool_size,
          url:
            url_with_password(
              "redis://:#{cluster.password}@#{slot.master.ip}:#{slot.master.port}",
              ""
            )
        ]
        |> LibRedis.Pool.new()
        |> tap(&LibRedis.Pool.start_link(pool: &1))

      client ->
        client
    end
  end

  @spec get_client_by_key(t(), bitstring()) :: LibRedis.Pool.t() | pid() | nil
  defp get_client_by_key(cluster, key) do
    target = LibRedis.SlotFinder.hash_slot(key)

    cluster.slot_store
    |> LibRedis.SlotStore.get()
    |> Enum.find(fn x -> x.start_slot <= target and x.end_slot >= target end)
    |> case do
      nil ->
        nil

      slot ->
        load_client(cluster, slot)
    end
  end
end
