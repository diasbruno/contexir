defmodule Contexir.Base do
  @moduledoc """
  Marks a module as Contexir-enabled.
  Imports `Contexir.Dispatch` for contextual dispatch.
  """

  defmacro __using__(_opts) do
    quote do
      import Contexir.Dispatch
    end
  end
end
