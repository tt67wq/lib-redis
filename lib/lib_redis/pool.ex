defmodule LibRedis.Pool do
  @moduledoc """
  wrap redix with nimble pool

  ## usage:

  add thie to application children:

  children = [
    ...
    {LibRedis.Pool, pool: LibRedis.Pool.new(name: Redis, url: "redis://:123456@localhost:6379")}
  ]
  """

  @behaviour NimblePool

  # type
  @type t :: %__MODULE__{
          name: GenServer.name(),
          url: String.t(),
          pool_size: non_neg_integer()
        }
  @type command_t :: [binary() | bitstring()]

  @enforce_keys ~w(name url pool_size)a

  defstruct @enforce_keys

  @doc """
  create new redis pool instance

  ## Examples

  iex> LibRedis.Pool.new()
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:name, :redis_pool)
      |> Keyword.put_new(:pool_size, 10)
      |> Keyword.put_new(:url, "redis://:123456@localhost:6379")

    struct(__MODULE__, opts)
  end

  @spec command(t(), command_t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def command(pool, command, opts \\ []) do
    pool_timeout = Keyword.get(opts, :pool_timeout, 5000)

    NimblePool.checkout!(
      pool.name,
      :checkout,
      fn _, conn ->
        conn
        |> Redix.command(command)
        |> then(fn x -> {x, conn} end)
      end,
      pool_timeout
    )
  end

  @spec pipeline(t(), [command_t()], keyword) ::
          {:ok, term()} | {:error, term()}
  def pipeline(pool, commands, opts \\ []) do
    pool_timeout = Keyword.get(opts, :pool_timeout, 5000)

    NimblePool.checkout!(
      pool.name,
      :checkout,
      fn _, conn ->
        conn
        |> Redix.pipeline(commands)
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
