defmodule Contexir.Dispatch do
  @moduledoc """
  Dispatches function calls through active layers, handling:
  - Context propagation
  - Layer predicates
  - Execution modes (:before, :around, :after)


  (defclass example () ())
  (defmethod compute ((x example))
  (format t "a Around (most specific)~%")
  (call-next-method)
  (format t "a Around (end)~%"))

  (defmethod compute :around ((x example))
  (format t "a Around (most specific)~%")
  (call-next-method)
  (format t "a Around (end)~%"))

  (defmethod compute :before ((x example))
  (format t "a Before~%"))

  (defmethod compute ((x example))
  (format t "a Primary~%"))

  (defmethod compute :after ((x example))
  (format t "a After~%"))

  (defclass extend-example (example) ())

  (defmethod compute :around ((x extend-example))
  (format t "b Around (most specific)~%")
  (call-next-method)
  (format t "b Around (end)~%"))

  (defmethod compute :before ((x extend-example))
  (format t "b Before~%"))

  (defmethod compute ((x extend-example))
  (format t "b Primary~%"))

  (defmethod compute :after ((x extend-example))
  (format t "b After~%"))

  b Around (most specific)
  a Around (most specific)
  b Before
  a Before
  b Primary
  a After
  b After
  a Around (end)
  b Around (end)
  """
  def call(module, fun, args) do
    {args, [ctx]} = extract_ctx(args)
    Contexir.Context.set_ctx(ctx)

    # NOTE(dias): We are running all the predicates before executing them.
    # Should it run the predicate after each layer?
    # Or add another predicate so we can "disable globally"
    # or "dynamic disable" in the depending on the current environment
    # and arguments the layer will be executed?
    layers =
      Contexir.Context.active_layers()
      |> Enum.filter(&predicate_active?(&1, module, fun, args, ctx))

    classify_and_run(layers, module, fun, args)
  end

  # Evaluate predicate for a given layer
  defp predicate_active?(layer, module, fun, args, ctx) do
    layer.__predicate__(module, fun, args, ctx)
  end

  # Classify layers by mode and execute
  defp classify_and_run(layers, module, fun, args) do
    {beforefn, aroundfn, afterfn} =
      Enum.reduce(layers, {[], [], []}, fn layer, {b, a, af} ->
        case partial_mode(layer, fun) do
          :before -> {[layer | b], a, af}
          :after  -> {b, a, [layer | af]}
          _       -> {b, [layer | a], af}
        end
      end)

    ctx = Contexir.Context.get_ctx()

    result = run_list_fn(Enum.reverse(aroundfn), module, fun, args)

    result
  end

  def run_list_fn([], _module, _fun, args) do
      List.first(args)
  end

  def run_list_fn(fns, module, fun, args) do
    run_chain(fns, module, fun, args)
  end

  defp run_chain([], module, fun, args) do
    IO.inspect(module)
    ctx = Contexir.Context.get_ctx()
    apply(module, fun, args ++ [ctx])
  end

  defp run_chain([layer | _rest], module, fun, args) do
    IO.inspect(layer)
    ctx = Contexir.Context.get_ctx()
    apply(layer, fun, [module | args] ++ [ctx])
  end


  defp partial_mode(layer, fun) do
    if function_exported?(layer, :__partial_mode__, 0) do
      {f, mode} = layer.__partial_mode__()
      if f == fun, do: mode, else: :around
    else
      :around
    end
  end

  defp extract_ctx(args) do
    case args do
      [] -> {[], nil}
      _  -> Enum.split(args, length(args) - 1)
    end
  end

  def continue(module, fun, args) do
    layers = Contexir.Context.active_layers()
    IO.inspect(layers)
    [_ | rest] = layers
    Process.put(:active_layers, rest)
    result = call(module, fun, args)
    Process.put(:active_layers, layers)
    result
  end
end
