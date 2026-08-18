defmodule Contexir.Layer do
  @moduledoc """
  Provides the DSL for defining *layers* — refinements to existing functions that can be
  activated dynamically at runtime.

  A “layer” is a module that declares zero or more *partials* (refinements) for
  existing functions, specifying how they should be modified under certain contexts.

  Through this DSL you can:
  - Define layers (via `deflayer`)
  - Define refinements (partials) for specific functions, choosing execution mode: `:before`, `:around`, or `:after` via `defpartial`.
  - Group layers (via `use_layers`) so you can compose sets of behavior as a single logical layer.

  This is the core mechanism that makes the rest of Contexir — dispatching,
  context propagation, and dynamic behavior — possible.

  ## DSL Overview

      deflayer LoggingLayer do
        refine SomeModule do
          # runs before the original function
          defpartial some_fun(arg1, arg2, ctx), mode: :before do
            IO.puts("about to call some_fun")
          end

          # wraps around the original and proceeds through `continue/1`
          defpartial some_fun(arg1, arg2, _ctx), mode: :around do
            IO.puts("entering")
            result = continue([arg1, arg2])
            IO.puts("exiting")
            result
          end

          # runs after the original function
          defpartial some_fun(_arg1, _arg2, _ctx), mode: :after do
            IO.puts("some_fun finished")
          end
        end
      end
  """

  @const_predicate_function_true {:fn, [],
                                  [
                                    {:->, [],
                                     [
                                       [
                                         {:_m, [], nil},
                                         {:_f, [], nil},
                                         {:_a, [], nil},
                                         {:_c, [], nil}
                                       ],
                                       true
                                     ]}
                                  ]}

  @doc """
  Returns compile-time metadata for a layer module.
  """
  def info(layer) do
    layer.__contexir_layer_info__()
  end

  @doc """
  Resolves layer composition metadata without activating the layers.

  Resolution expands `use_layers`, removes duplicate layers while preserving the
  first occurrence, and validates `requires` and `conflicts_with` relationships.
  """
  def resolve(layers) do
    resolved =
      layers
      |> Enum.flat_map(&expand_layer/1)
      |> uniq()

    with :ok <- validate_requires(resolved),
         :ok <- validate_conflicts(resolved) do
      {:ok, resolved}
    end
  end

  @doc """
  Resolves layer composition metadata or raises when relationships are invalid.
  """
  def resolve!(layers) do
    case resolve(layers) do
      {:ok, resolved} ->
        resolved

      {:error, reason} ->
        raise ArgumentError, "invalid layer composition: #{inspect(reason)}"
    end
  end

  @doc """
  Resolves declarative context rules against a context map.
  """
  def resolve_context(context_module, ctx) do
    context_module.__contexir_context_layers__(ctx)
    |> resolve()
  end

  @doc """
  Resolves declarative context rules or raises when relationships are invalid.
  """
  def resolve_context!(context_module, ctx) do
    context_module.__contexir_context_layers__(ctx)
    |> resolve!()
  end

  @doc """
  Declares a context module that can activate layers from context values.
  """
  defmacro defcontext(name, do: block) do
    quote do
      defmodule unquote(name) do
        import Contexir.Layer, only: [layer: 2]

        Module.register_attribute(__MODULE__, :contexir_context_layers, accumulate: true)

        unquote(block)

        def __contexir_context_layers__(ctx) do
          @contexir_context_layers
          |> Enum.reverse()
          |> Enum.flat_map(&__contexir_context_layer__(ctx, &1))
        end

        def __contexir_context_layer__(_ctx, _layer), do: []
      end
    end
  end

  @doc """
  Declares a new **layer module**.

  The `deflayer` macro defines a standard Elixir module configured as a Contexir
  layer. Inside the block, you can use `defpartial/3` to define refinements for
  specific base module functions.

  ## Example

      deflayer LoggingLayer do
        refine Account do
          defpartial withdraw(_acc, amt, _ctx), mode: :before do
            IO.puts("[BEFORE] withdrawing \#{amt}")
          end
        end
      end
  """
  defmacro deflayer(name, opts \\ [], do: block) do
    predicate = Keyword.get(opts, :when, @const_predicate_function_true)

    {:fn, _x,
     [
       {:->, _y,
        [
          args,
          body
        ]}
     ]} = predicate

    quote do
      defmodule unquote(name) do
        import Contexir.Layer

        @contexir_predicate? unquote(predicate != @const_predicate_function_true)
        Module.register_attribute(__MODULE__, :contexir_partials, accumulate: true)
        Module.register_attribute(__MODULE__, :contexir_requires, accumulate: true)
        Module.register_attribute(__MODULE__, :contexir_conflicts_with, accumulate: true)
        Module.register_attribute(__MODULE__, :contexir_before, accumulate: true)
        Module.register_attribute(__MODULE__, :contexir_after, accumulate: true)
        Module.register_attribute(__MODULE__, :included_layers, accumulate: false)

        def __predicate__(unquote_splicing(args)) do
          unquote(body)
        end

        unquote(block)

        def __contexir_layer_info__ do
          %{
            module: __MODULE__,
            partials: Enum.reverse(@contexir_partials),
            includes: @included_layers || [],
            requires: Enum.reverse(@contexir_requires),
            conflicts_with: Enum.reverse(@contexir_conflicts_with),
            before: Enum.reverse(@contexir_before),
            after: Enum.reverse(@contexir_after),
            predicate?: @contexir_predicate?
          }
        end

        @doc """
        Default case.
        """
        def has_mode_defined(_mod, _fun, _mode), do: false
      end
    end
  end

  @doc """
  Defines a **partial function** — a refinement of an existing function
  from another module.

  The `defpartial` macro declares behavior for a specific *mode*:
  `:before`, `:around`, or `:after`.

  - `:before` — runs before the primary function
  - `:around` — wraps the next layer or base function (call `continue/1`)
  - `:after` — runs after the primary function returns

  ## Example

      defpartial Account.withdraw(acc, amt, _ctx), mode: :around do
        IO.puts("[AROUND] start")
        result = continue([acc, amt])
        IO.puts("[AROUND] end")
        result
      end
  """
  defmacro defpartial(signature, opts \\ [], do: body) do
    {the_module, fun, args} = partial_signature(signature, __CALLER__)

    mode = Keyword.get(opts, :mode, :around)

    quote do
      @contexir_partials %{
        module: unquote(the_module),
        function: unquote(fun),
        mode: unquote(mode)
      }

      def unquote(fun)(unquote(the_module), unquote(mode), unquote_splicing(args)) do
        import Contexir.Dispatch, only: [continue: 1, continue: 3]
        unquote(body)
      end

      def has_mode_defined(unquote(the_module), unquote(fun), unquote(mode)), do: true
    end
  end

  defp partial_signature(signature, caller) do
    case Macro.decompose_call(signature) do
      {target, fun, args} ->
        {Macro.expand(target, caller), fun, args}

      {fun, args} ->
        case Module.get_attribute(caller.module, :contexir_refine_target) do
          nil ->
            raise ArgumentError,
                  "local defpartial requires a target module. Wrap it in refine Target do ... end"

          target ->
            {target, fun, args}
        end
    end
  end

  @doc """
  Defines partials for a single target module.

  Inside a `refine` block, `defpartial` may omit the target module:

      deflayer LoggingLayer do
        refine Account do
          defpartial withdraw(account, amount, _ctx), mode: :around do
            continue([account, amount])
          end
        end
      end
  """
  defmacro refine(target, do: block) do
    target = Macro.expand(target, __CALLER__)
    block = rewrite_refine_block(block, target)

    quote do
      unquote(block)
    end
  end

  defp rewrite_refine_block(block, target) do
    Macro.prewalk(block, fn
      {:defpartial, meta, [signature, opts, body]} ->
        {:defpartial, meta, [refined_signature(signature, target), opts, body]}

      {:defpartial, meta, [signature, body]} ->
        {:defpartial, meta, [refined_signature(signature, target), body]}

      ast ->
        ast
    end)
  end

  defp refined_signature({fun, meta, args}, target) when is_atom(fun) and is_list(args) do
    {{:., meta, [target, fun]}, meta, args}
  end

  defp refined_signature(signature, _target), do: signature

  @doc """
  Includes or *reuses* other layers inside the current one.

  This macro allows grouping multiple layers together under a single layer
  name, so they can be activated as a unit. The composed layer will
  automatically delegate to all included layers during dispatch.

  ## Example

      deflayer SecureLayer do
        use_layers [AuthLayer, LoggingLayer]
      end

      Contexir.with_layers [SecureLayer] do
        Account.withdraw(%{balance: 100}, 10, %{user_authenticated: true})
      end

  This is equivalent to activating `[AuthLayer, LoggingLayer]` together.
  """
  defmacro use_layers(layers) do
    quote do
      Module.put_attribute(__MODULE__, :included_layers, unquote(layers))
      def __included_layers__, do: @included_layers
    end
  end

  @doc """
  Declares that the current layer requires another layer to be active.
  """
  defmacro requires(layer) do
    quote do
      @contexir_requires unquote(layer)
    end
  end

  @doc """
  Declares that the current layer cannot be active with another layer.
  """
  defmacro conflicts_with(layer) do
    quote do
      @contexir_conflicts_with unquote(layer)
    end
  end

  @doc """
  Declares that the current layer should run before another layer.
  """
  defmacro before(layer) do
    quote do
      @contexir_before unquote(layer)
    end
  end

  @doc """
  Declares that the current layer should run after another layer.
  """
  defmacro after_layer(layer) do
    quote do
      @contexir_after unquote(layer)
    end
  end

  @doc """
  Declares a context-activated layer inside `defcontext`.
  """
  defmacro layer(layer, opts) do
    predicate = Keyword.fetch!(opts, :when)

    quote do
      @contexir_context_layers unquote(layer)

      def __contexir_context_layer__(ctx, unquote(layer)) do
        if unquote(predicate).(ctx), do: [unquote(layer)], else: []
      end
    end
  end

  defp expand_layer(layer) do
    case info(layer).includes do
      [] -> [layer]
      layers -> Enum.flat_map(layers, &expand_layer/1)
    end
  end

  defp uniq(layers) do
    layers
    |> Enum.reduce({[], MapSet.new()}, fn layer, {layers, seen} ->
      if MapSet.member?(seen, layer) do
        {layers, seen}
      else
        {[layer | layers], MapSet.put(seen, layer)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp validate_requires(layers) do
    layer_set = MapSet.new(layers)

    layers
    |> Enum.flat_map(fn layer ->
      info(layer).requires
      |> Enum.reject(&MapSet.member?(layer_set, &1))
      |> Enum.map(&%{layer: layer, requires: &1})
    end)
    |> case do
      [] -> :ok
      missing -> {:error, {:missing_requirements, missing}}
    end
  end

  defp validate_conflicts(layers) do
    layer_set = MapSet.new(layers)

    layers
    |> Enum.flat_map(fn layer ->
      info(layer).conflicts_with
      |> Enum.filter(&MapSet.member?(layer_set, &1))
      |> Enum.map(&%{layer: layer, conflicts_with: &1})
    end)
    |> case do
      [] -> :ok
      conflicts -> {:error, {:conflicting_layers, conflicts}}
    end
  end
end
