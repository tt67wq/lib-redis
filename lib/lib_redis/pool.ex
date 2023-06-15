defmodule LibRedis.Pool do
  @external_resource "docs/pool.md"
  @moduledoc "docs/pool.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  @behaviour NimblePool

  @pool_opts_schema [
    name: [
      type: {:or, [:atom, :pid, {:tuple, [:atom, :atom, :any]}]},
      default: :redis_pool,
      doc: "The name of the pool"
    ],
    pool_size: [
      type: :non_neg_integer,
      default: 10,
      doc: "The size of the pool"
    ],
    url: [
      type: :string,
      required: true,
      doc: "The url of the redis server, like redis://:123456@localhost:6379"
    ]
  ]

  # type
  @type t :: %__MODULE__{
          name: GenServer.name(),
          url: String.t(),
          pool_size: non_neg_integer()
        }
  @type pool_opts_t :: keyword(unquote(NimbleOptions.option_typespec(@pool_opts_schema)))

  @enforce_keys ~w(name url pool_size)a

  defstruct @enforce_keys

  @doc """
  create new redis pool instance

  ## Options
  #{NimbleOptions.docs(@pool_opts_schema)}

  ## Examples

      iex> LibRedis.Pool.new()
  """
  @spec new(pool_opts_t()) :: t()
  def new(opts \\ []) do
    opts =
      opts
      |> NimbleOptions.validate!(@pool_opts_schema)

    struct(__MODULE__, opts)
  end

  @doc """
  delegate to Redix.command/2

  ## Examples

      iex> LibRedis.Pool.command(pool, ["SET", "foo", "bar"])
      {:ok, "OK"}
  """
  @spec command(t() | pid() | atom(), Typespecs.command_t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def command(instance, command, opts \\ [])

  def command(pool, command, opts) when is_struct(pool) do
    command(pool.name, command, opts)
  end

  def command(name, command, opts) do
    {pool_timeout, opts} = Keyword.pop(opts, :pool_timeout, 5000)

    NimblePool.checkout!(
      name,
      :checkout,
      fn _, conn ->
        conn
        |> Redix.command(command, opts)
        |> then(fn x -> {x, conn} end)
      end,
      pool_timeout
    )
  end

  @doc """
  delegate to Redix.pipeline/2

  ## Examples

      iex> LibRedis.Pool.pipeline(pool, [["SET", "foo", "bar"], ["SET", "bar", "foo"]])
      {:ok, ["OK", "OK"]]}
  """
  @spec pipeline(t() | pid() | atom(), [Typespecs.command_t()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def pipeline(pool, commands, opts \\ [])

  def pipeline(pool, commands, opts) when is_struct(pool) do
    pipeline(pool.name, commands, opts)
  end

  def pipeline(name, commands, opts) do
    {pool_timeout, opts} = Keyword.pop(opts, :pool_timeout, 5000)

    NimblePool.checkout!(
      name,
      :checkout,
      fn _, conn ->
        conn
        |> Redix.pipeline(commands, opts)
        |> then(fn x -> {x, conn} end)
      end,
      pool_timeout
    )
  end

  @impl NimblePool
  @spec init_worker(String.t()) :: {:ok, pid, any}
  def init_worker(redis_url = pool_state) do
    {:ok, conn} = Redix.start_link(redis_url)
    {:ok, conn, pool_state}
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, conn, pool_state) do
    {:ok, conn, conn, pool_state}
  end

  @impl NimblePool
  def handle_checkin(conn, _, _old_conn, pool_state) do
    {:ok, conn, pool_state}
  end

  @impl NimblePool
  def handle_info(:close, _conn), do: {:remove, :closed}
  def handle_info(_, conn), do: {:ok, conn}

  @impl NimblePool
  def handle_ping(conn, _pool_state) do
    Redix.command(conn, ["PING"])
    |> case do
      {:ok, "PONG"} -> {:ok, conn}
      _ -> {:remove, :closed}
    end
  end

  @impl NimblePool
  def terminate_worker(_reason, conn, pool_state) do
    Redix.stop(conn)
    {:ok, pool_state}
  end

  def child_spec(opts) do
    pool = Keyword.fetch!(opts, :pool)
    %{id: {__MODULE__, pool.name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  start redis with nimble pool

  ## Examples

      iex> LibRedis.Pool.start_link(pool: LibRedis.Pool.new())
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {pool, opts} = Keyword.pop(opts, :pool)

    opts =
      opts
      |> Keyword.put_new(:worker, {__MODULE__, pool.url})
      |> Keyword.put_new(:pool_size, pool.pool_size)
      |> Keyword.put_new(:worker_idle_timeout, 10_000)
      |> Keyword.put_new(:name, pool.name)

    NimblePool.start_link(opts)
  end
end
