defmodule Contexir.Context do
  @moduledoc """
  Manages the process-local active layer stack and shared context map.
  """

  @doc"""
  This is where everything gets executed.
  """
  def with_layers(layers, mod, fun, args) do
    old = Process.get(:active_layers, [])
    expanded = Enum.flat_map(layers, &expand_layer/1)
    Process.put(:active_layers, expanded ++ old)

    IO.inspect(fun)

    try do
      Contexir.Dispatch.call(mod, fun, args)
    after
      Process.put(:active_layers, old)
    end
  end

  # Activate a layer (recursively expands grouped layers)
  def activate(layer) do
    expanded = expand_layer(layer)
    layers = Process.get(:active_layers, [])
    Process.put(:active_layers, expanded ++ layers)
  end

  # Deactivate a single layer
  def deactivate(layer) do
    layers = Process.get(:active_layers, [])
    Process.put(:active_layers, List.delete(layers, layer))
  end

  # Current active layers
  def active_layers, do: Process.get(:active_layers, [])

  # Shared context map
  def get_ctx, do: Process.get(:contexir_ctx, %{})
  def set_ctx(ctx), do: Process.put(:contexir_ctx, ctx)

  def update_ctx(fun) when is_function(fun, 1) do
    set_ctx(fun.(get_ctx()))
  end

  # Expand grouped layers recursively
  defp expand_layer(layer) do
    if function_exported?(layer, :__included_layers__, 0) do
      Enum.flat_map(layer.__included_layers__(), &expand_layer/1)
    else
      [layer]
    end
  end
end
