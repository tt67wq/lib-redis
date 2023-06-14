defmodule LibRedis.Error do
  @moduledoc """
  redis error
  """

  @type t :: %__MODULE__{
          message: bitstring()
        }

  defexception [:message]

  def new(message) do
    %__MODULE__{message: message}
  end
end
