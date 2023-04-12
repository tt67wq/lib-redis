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
          poolsize: non_neg_integer()
        }

  @enforce_keys ~w(name mode url password poolsize)a

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
      |> Keyword.put_new(:poolsize, 10)

    struct(__MODULE__, opts)
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
        LibRedis.Standalone.start_link(
          pool: Standalone.new(name: redis.name, url: redis.url, pool_size: redis.poolsize)
        )

      :cluster ->
        Agent.start_link(fn -> :ok end, name: redis.name)
    end
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
