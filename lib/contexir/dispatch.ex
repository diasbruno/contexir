defmodule Contexir.Dispatch do
  @moduledoc """
  Internal module responsible for executing layered function calls.

  `Contexir.Dispatch` builds and executes an **execution plan** composed of
  three ordered lists — the *arounds*, *befores*, and *afters* — that define
  how each active layer participates in a function call.

  ## Execution Order

  The dispatcher enforces this consistent call sequence for all active layers [A, B]:

      A around
        B around
          A before
          B before
            primary
          B after
          A after
        B around end
      A around end

  Where each layer’s `:around` must explicitly call `continue/1` to proceed to
  the next layer or the base function. If a layer omits that call, execution
  stops there — the layer effectively captures the call.

  `Contexir.Dispatch` maintains no global state. All layer and context data
  are stored process-locally to ensure concurrency safety.
  """

  @execution_key :contexir_execution_plan
  @current_call_key :contexir_current_call

  defp extract_ctx(args) do
    case args do
      [] ->
        {[], nil}

      _ ->
        {args, [ctx]} = Enum.split(args, length(args) - 1)
        {args, ctx}
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
    {around, before, after_} =
      Enum.reduce(layers, {[], [], []}, fn layer, {around, before, after_} ->
        around =
          if layer.has_mode_defined(module, fun, :around), do: [layer | around], else: around

        before =
          if layer.has_mode_defined(module, fun, :before), do: [layer | before], else: before

        after_ =
          if layer.has_mode_defined(module, fun, :after), do: [layer | after_], else: after_

        {around, before, after_}
      end)

    {Enum.reverse(around), Enum.reverse(before), after_}
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
    old_ctx = Contexir.Context.get_ctx()
    Contexir.Context.set_ctx(ctx)

    layers =
      Contexir.Context.active_layers()
      |> Enum.filter(&predicate_active?(&1, module, fun, args, ctx))

    execution_plan = build_plan(layers, module, fun)

    old_execution_plan = Process.get(@execution_key)
    old_current_call = Process.get(@current_call_key)
    Process.put(@execution_key, execution_plan)
    Process.put(@current_call_key, {module, fun})

    try do
      continue(module, fun, args)
    after
      Contexir.Context.set_ctx(old_ctx)
      Process.put(@execution_key, old_execution_plan)
      Process.put(@current_call_key, old_current_call)
    end
  end

  @doc """
  Advances the current execution to the next layer or to the primary function.

  `continue/3` can be called **inside an `:around` partial** to delegate
  control to the next layer in the chain. If there are no more `:around`
  layers left, it executes all `:before` and `:after` phases and finally
  calls the primary function.

  The `module` and `fun` refer to the base function being refined,
  and `args` is the list of arguments to forward.

  ## Example

      defpartial Account.withdraw(acc, amt, _ctx), mode: :around do
        IO.puts("Start")
        result = continue(Account, :withdraw, [acc, amt])
        IO.puts("End")
        result
      end

  If an `:around` partial does **not** call `continue`, execution
  halts at that layer and returns.

  This function is used within Contexir’s layer DSL and
  should only be called from inside `defpartial …, mode: :around` blocks.
  """
  def continue(module, fun, args) do
    case Process.get(@execution_key) do
      {[], before, after_} ->
        Enum.each(before, fn layer ->
          ctx = Contexir.Context.get_ctx()
          apply(layer, fun, [module, :before | args] ++ [ctx])
        end)

        ctx = Contexir.Context.get_ctx()
        result = apply(module, fun, args ++ [ctx])

        Enum.each(after_, fn layer ->
          ctx = Contexir.Context.get_ctx()
          apply(layer, fun, [module, :after | args] ++ [ctx])
        end)

        result

      {around, before, after_} ->
        [current | rest] = around
        Process.put(@execution_key, {rest, before, after_})
        ctx = Contexir.Context.get_ctx()
        apply(current, fun, [module, :around | args] ++ [ctx])
    end
  end

  @doc """
  Advances the current execution using the module and function being refined.

  This shorthand is intended for `:around` partials:

      defpartial Account.withdraw(account, amount, _ctx), mode: :around do
        continue([account, amount])
      end

  It is equivalent to `continue(Account, :withdraw, [account, amount])`.
  """
  def continue(args) when is_list(args) do
    case Process.get(@current_call_key) do
      {module, fun} ->
        continue(module, fun, args)

      nil ->
        raise RuntimeError, "continue/1 can only be called during Contexir dispatch"
    end
  end
end
