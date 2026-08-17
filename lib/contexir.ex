defmodule Contexir do
  @moduledoc """
  **Contexir** brings **Context-Oriented Programming (COP)** to Elixir — a way to build
  *context-aware, composable, and dynamically adaptable* systems.

  Instead of relying on rigid inheritance or compile-time behavior, Contexir lets you
  define *layers* that can modify or extend function behavior **at runtime**, in a
  controlled and composable manner.

  Layers are activated dynamically using `Contexir.with_layers/2` and automatically
  deactivated when the block exits. Each process has its own active layer stack,
  keeping Contexir completely **isolated and concurrency-safe**.

  ## Overview

  A *layer* is a module that can refine existing functions using *partial definitions*:

  - `:around` — wraps the next layer or primary function (must call `continue/3` to proceed)
  - `:before` — runs before the main function
  - `:after` — runs after the main function returns

  These refinements compose cleanly and follow a predictable execution plan.

  ---

  ## Example

      defmodule Account do
        use Contexir.Base

        def withdraw(acc, amt, _ctx) do
          IO.puts("primary")
          %{acc | balance: acc.balance - amt}
        end
      end

      deflayer LoggingLayer do
        defpartial Account.withdraw(acc, amt, ctx), mode: :before do
          IO.puts("[BEFORE] Logging withdrawal of \#{amt}")
        end

        defpartial Account.withdraw(acc, amt, ctx), mode: :around do
          IO.puts("[AROUND] Start transaction")
          result = continue(Account, :withdraw, [acc, amt, ctx])
          IO.puts("[AROUND] End transaction")
          result
        end

        defpartial Account.withdraw(_acc, _amt, _ctx), mode: :after do
          IO.puts("[AFTER] Completed")
        end
      end

      Contexir.with_layers [LoggingLayer] do
        Account.withdraw(%{balance: 500}, 100, %{})
      end

  **Output:**

      [AROUND] Start transaction
      [BEFORE] Logging withdrawal of 100
      primary
      [AFTER] Completed
      [AROUND] End transaction

  ---

  ## Execution Model

  When multiple layers are active, execution follows this pattern:

  | Phase | Direction | Description |
  |--------|------------|-------------|
  | `:around` | outer → inner | Wraps the rest of the call chain. Must call `continue/3`. |
  | `:before` | outer → inner | Runs before the primary function. |
  | `:primary` | — | The original function being refined. |
  | `:after` | inner → outer | Runs after the primary function returns. |

  Example for `[A, B]` active layers:

      A around
        B around
          A before
          B before
            primary
          B after
          A after
        B around end
      A around end
  """

  defp extract_call_info(target) do
    {{:., _x,
      [
        {:__aliases__, _y, mod},
        fun
      ]}, _z, args} = target

    {mod, fun, args}
  end

  @doc """
  Temporarily activates a list of layers for the duration of a block.

  The given `layers` are added to the current process's active layer stack
  while the block runs, and automatically removed afterward.

  ## Example

      Contexir.with_layers [LoggingLayer], do:
        Account.withdraw(%{balance: 100}, 10, %{})

  Layers are scoped to the current process and do not affect other concurrent
  executions.
  """
  defmacro with_layers(layers, target) do
    {mod, fun, args} = extract_call_info(target)

    quote do
      Contexir.Context.with_layers(
        unquote(layers),
        unquote(Module.concat(mod)),
        unquote(fun),
        unquote(args)
      )
    end
  end

  @doc """
  Marks a module as a *context-aware base module*.

  When you `use Contexir`, the module becomes compatible with the Contexir
  dispatch system — allowing its functions to be refined dynamically.

  The macro injects the necessary setup so that calls to the module’s
  functions are automatically routed through the Contexir dispatcher.

  ## Example

      defmodule Account do
        use Contexir

        def withdraw(acc, amt, _ctx) do
          %{acc | balance: acc.balance - amt}
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      import Contexir.Dispatch
    end
  end
end
