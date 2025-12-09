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
        # runs before the original function
        defpartial SomeModule.some_fun(arg1, arg2, ctx), mode: :before do
          IO.puts("about to call some_fun")
        end

        # wraps around the original — must call `continue/3`
        defpartial SomeModule.some_fun(arg1, arg2, ctx), mode: :around do
          IO.puts("entering")
          result = continue(SomeModule, :some_fun, [arg1, arg2, ctx])
          IO.puts("exiting")
          result
        end

        # runs after the original function
        defpartial SomeModule.some_fun(arg1, arg2, ctx), mode: :after do
          IO.puts("some_fun finished")
        end
      end
  """

  @const_predicate_function_true {:fn, [],
                                  [
                                    {:->, [],
                                    [
                                      [{:_m, [], nil}, {:_f, [], nil}, {:_a, [], nil}, {:_c, [], nil}],
                                      true
                                    ]}
                                  ]}

  @doc """
  Declares a new **layer module**.

  The `deflayer` macro defines a standard Elixir module configured as a Contexir
  layer. Inside the block, you can use `defpartial/3` to define refinements for
  specific base module functions.

  ## Example

      deflayer LoggingLayer do
        defpartial Account.withdraw(acc, amt, ctx), mode: :before do
          IO.puts("[BEFORE] withdrawing \#{amt}")
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

        def __predicate__(unquote_splicing(args)) do
          unquote(body)
        end

        unquote(block)

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
  - `:around` — wraps the next layer or base function (must call `continue/3`)
  - `:after` — runs after the primary function returns

  ## Example

      defpartial Account.withdraw(acc, amt, ctx), mode: :around do
        IO.puts("[AROUND] start")
        result = continue(Account, :withdraw, [acc, amt, ctx])
        IO.puts("[AROUND] end")
        result
      end
  """
  defmacro defpartial(signature, opts \\ [], do: body) do
    {{:., _x, [{_y, _m, mod}, fun]}, _z, args} = signature

    the_module = Module.concat(mod)

    mode = Keyword.get(opts, :mode, :around)

    quote do
      def unquote(fun)(unquote(the_module), unquote(mode), unquote_splicing(args)) do
        import Contexir.Dispatch, only: [continue: 3]
        unquote(body)
      end

      def has_mode_defined(unquote(the_module), unquote(fun), unquote(mode)), do: true
    end
  end

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
end
