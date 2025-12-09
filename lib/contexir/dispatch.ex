defmodule Contexir.Dispatch do
  @moduledoc """
  Internal module responsible for executing layered function calls.

  `Contexir.Dispatch` builds and executes an **execution plan** composed of
  three ordered lists — the *arounds*, *befores*, and *afters* — that define
  how each active layer participates in a function call.

  ## Execution Order

  The dispatcher enforces this consistent call sequence for all active layers [A, B]:

      A:around
      B:around
      A:before
      B:before
      primary
      B:after
      A:after
      A:around end
      B:around end

  Where each layer’s `:around` must explicitly call `continue/3` to proceed to
  the next layer or the base function. If a layer omits that call, execution
  stops there — the layer effectively captures the call.

  `Contexir.Dispatch` maintains no global state. All layer and context data
  are stored process-locally to ensure concurrency safety.
  """

  defp extract_ctx(args) do
    case args do
      [] -> {[], nil}
      _  -> Enum.split(args, length(args) - 1)
    end
  end

  # Check whether a layer is inactive.
  defp predicate_active?(layer, module, fun, args, ctx) do
    layer.__predicate__(module, fun, args, ctx)
  end

  # Returns a tuple-3 with:
  # - Layers with around
  # - with before
  # - with after
  defp build_plan(layers, module, fun) do
    {a, b, c} = Enum.reduce(layexrs, {[], [], []}, fn layer, {a, b, c} ->
      aa = if layer.has_mode_defined(module, fun, :around), do: [layer | a], else: a
      bb = if layer.has_mode_defined(module, fun, :before), do: [layer | b], else: b
      cc = if layer.has_mode_defined(module, fun, :after), do: [layer | c], else: c
      {aa, bb, cc}
    end)

    {Enum.reverse(a), Enum.reverse(b), c}
  end

  @doc """
  Dispatches a function call through all currently active layers.

  This is the **entry point** used internally by Contexir when a function
  defined with `use Contexir` is invoked. It builds an execution plan from
  the currently active layers and executes it according to Contexir’s
  layer order model (`:around`, `:before`, `:after`).

  The `module` and `fun` identify the base function being called,
  and `args` represents the argument list (including the optional context map).

  ## Example (internal)

      Contexir.Dispatch.call(Account, :withdraw, [%{balance: 100}, 10, %{}])
  """
  def call(module, fun, args) do
    {args, ctx} = extract_ctx(args)
    Contexir.Context.set_ctx(ctx)

    layers =
      Contexir.Context.active_layers()
      |> Enum.filter(&predicate_active?(&1, module, fun, args, ctx))

    execution_plan = build_plan(layers, module, fun)

    Process.put(:active_layers, execution_plan)

    continue(module, fun, args)
  end

  @doc """
  Advances the current execution to the next layer or to the primary function.

  `continue/3` must be called **inside an `:around` partial** to delegate
  control to the next layer in the chain. If there are no more `:around`
  layers left, it executes all `:before` and `:after` phases and finally
  calls the primary function.

  The `module` and `fun` refer to the base function being refined,
  and `args` is the list of arguments to forward.

  ## Example

      defpartial Account.withdraw(acc, amt, ctx), mode: :around do
        IO.puts("Start")
        result = continue(Account, :withdraw, [acc, amt, ctx])
        IO.puts("End")
        result
      end

  If an `:around` partial does **not** call `continue/3`, execution
  halts at that layer and returns.

  This function is used within Contexir’s layer DSL and
  should only be called from inside `defpartial …, mode: :around` blocks.
  """
  def continue(module, fun, args) do
    case Process.get(:active_layers) do
      {[], b, _c} ->
        Enum.each b, fn layer ->
          ctx = Contexir.Context.get_ctx()
          apply(layer, fun, [module, :before | args] ++ [ctx])
        end
        ctx = Contexir.Context.get_ctx()
        result = apply(module, fun, args ++ [ctx])
        Enum.each b, fn layer ->
          ctx = Contexir.Context.get_ctx()
          apply(layer, fun, [module, :after | args] ++ [ctx])
        end
        result
      {around, b, c} ->
        [current | rest] = around
        Process.put(:active_layers, {rest, b, c})
        ctx = Contexir.Context.get_ctx()
        apply(current, fun, [module, :around | args] ++ ctx)
    end
  end
end
