defmodule Contexir.Task do
  @moduledoc """
  Task helpers that run functions with the caller's current Contexir scope.
  """

  @doc """
  Starts a task with the caller's current active layers and context.
  """
  def async(fun) when is_function(fun, 0) do
    layers = Contexir.Context.active_layers()
    ctx = Contexir.Context.current()

    Task.async(fn ->
      Contexir.Context.with_scope(layers, ctx, fun)
    end)
  end

  @doc """
  Starts a task with the caller's current active layers and context.
  """
  def async(module, function, args)
      when is_atom(module) and is_atom(function) and is_list(args) do
    async(fn -> apply(module, function, args) end)
  end

  @doc """
  Awaits a Contexir task.
  """
  def await(task, timeout \\ 5000) do
    Task.await(task, timeout)
  end
end
