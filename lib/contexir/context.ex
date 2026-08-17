defmodule Contexir.Context do
  @moduledoc """
  Manages the process-local active layer stack and shared context map.
  """

  @doc """
  This is where everything gets executed.
  """
  def with_layers(layers, mod, fun, args) do
    old = Process.get(:active_layers, [])
    expanded = Contexir.Layer.resolve!(layers)
    Process.put(:active_layers, expanded ++ old)

    try do
      Contexir.Dispatch.call(mod, fun, args)
    after
      Process.put(:active_layers, old)
    end
  end

  # Activate a layer (recursively expands grouped layers)
  def activate(layer) do
    expanded = Contexir.Layer.resolve!([layer])
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

  @doc """
  Returns the current process-local context.
  """
  def current, do: get_ctx()

  @doc """
  Returns a value from the current context.
  """
  def get(key, default \\ nil) do
    Map.get(get_ctx(), key, default)
  end

  @doc """
  Sets a value in the current context.
  """
  def put(key, value) do
    update_ctx(&Map.put(&1, key, value))
  end

  @doc """
  Updates a value in the current context.
  """
  def update(key, initial, fun) when is_function(fun, 1) do
    update_ctx(&Map.update(&1, key, initial, fun))
  end

  @doc """
  Runs a function with a temporary process-local context.
  """
  def with_context(ctx, fun) when is_function(fun, 0) do
    old = get_ctx()
    set_ctx(ctx)

    try do
      fun.()
    after
      set_ctx(old)
    end
  end
end
