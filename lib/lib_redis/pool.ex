defmodule LibRedis.Pool do
  @moduledoc """
  wrap redix with nimble pool

  ## usage:

  add thie to application children:

  children = [
    ...
    {LibRedis.Pool, url: "redis://:123456@localhost:6379", name: Redis}
  ]
  """

  @behaviour NimblePool

  # type

  @type command_t :: [binary() | bitstring()]
  @type redis_opts :: [name: atom(), url: String.t()]
  @type on_start() ::
          {:ok, pid()}
          | :ignore
          | {:error, {:already_started, pid()} | {:shutdown, term()} | term()}

  @spec command(atom | pid | {atom, any} | {:via, atom, any}, command_t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def command(pool, command, opts \\ []) do
    pool_timeout = Keyword.get(opts, :pool_timeout, 5000)

    NimblePool.checkout!(
      pool,
      :checkout,
      fn _, conn ->
        conn
        |> Redix.command(command)
        |> then(fn x -> {x, conn} end)
      end,
      pool_timeout
    )
  end

  @spec pipeline(atom | pid | {atom, any} | {:via, atom, any}, [command_t()], keyword) ::
          {:ok, term()} | {:error, term()}
  def pipeline(pool, commands, opts \\ []) do
    pool_timeout = Keyword.get(opts, :pool_timeout, 5000)

    NimblePool.checkout!(
      pool,
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

    with {:ok, "PONG"} <- Redix.command(conn, ["PING"]) do
      {:ok, conn, conn, pool_state}
    else
      _ -> {:remove, :closed, pool_state}
    end
  end

  @impl NimblePool
  def handle_checkin(conn, _, _old_conn, pool_state) do
    {:ok, conn, pool_state}
  end

  @impl NimblePool
  def handle_info(:close, _conn), do: {:remove, :closed}
  def handle_info(_, conn), do: {:ok, conn}

  @impl NimblePool
  def terminate_worker(_reason, conn, pool_state) do
    Redix.stop(conn)
    {:ok, pool_state}
  end

  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)
    %{id: {__MODULE__, name}, start: {__MODULE__, :start_link, [opts]}}
  end

  @spec start_link(redis_opts()) :: on_start()
  def start_link(opts) do
    {url, opts} = Keyword.pop(opts, :url)

    opts =
      opts
      |> Keyword.put_new(:worker, {__MODULE__, url})

    NimblePool.start_link(opts)
  end
end
