defmodule Contexir do
  @moduledoc """
  Provides `with_layers` for scoped activation.
  """
  defmacro with_layers(layers, target) do
    {{:., _x,
      [
        {:__aliases__, _y,
         mod},
        fun
      ]}, _z,
     args} = target
    quote do
      Contexir.Context.with_layers(unquote(layers), unquote(Module.concat(mod)), unquote(fun), unquote(args))
    end
  end
end
