defmodule LibRedis.Typespecs do
  @moduledoc false

  @type name :: atom()
  @type url :: bitstring()
  @type password :: bitstring()
  @type on_start :: {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}
end
