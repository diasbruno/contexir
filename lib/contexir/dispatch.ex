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


  # Result:

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
  # - Layers with aroundg
  # - with before
  # - with after
  defp build_plan(layers, module, fun) do
    {a, b, c} = Enum.reduce(layers, {[], [], []}, fn layer, {a, b, c} ->
      aa = if layer.has_mode_defined(module, fun, :around), do: [layer | a], else: a
      bb = if layer.has_mode_defined(module, fun, :before), do: [layer | b], else: b
      cc = if layer.has_mode_defined(module, fun, :after), do: [layer | c], else: c
      {aa, bb, cc}
    end)

    {Enum.reverse(a), Enum.reverse(b), c}
  end

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
