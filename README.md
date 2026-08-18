# Contexir

![contexir](https://raw.githubusercontent.com/diasbruno/contexir/refs/heads/development/assets/github-banner.png "contexir")

Context-oriented programming for Elixir.

Contexir lets you define layers that refine function behavior at runtime.
Layers are activated dynamically, scoped to the current BEAM process, and can be
selected explicitly or from context values.

## Installation

Add Contexir to your `mix.exs`:

```elixir
def deps do
  [
    {:contexir, "0.2.0"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Core Concepts

### Base Modules

Use `Contexir` in modules whose functions can be refined by layers:

```elixir
defmodule Account do
  use Contexir

  def withdraw(account, amount, _ctx) do
    %{account | balance: account.balance - amount}
  end
end
```

Contexir expects the final argument to be a context value, usually a map.

### Layers

A layer defines partial behavior for an existing function.

```elixir
import Contexir.Layer

deflayer LoggingLayer do
  defpartial Account.withdraw(_account, amount, _ctx), mode: :before do
    IO.puts("withdrawing #{amount}")
  end

  defpartial Account.withdraw(account, amount, _ctx), mode: :around do
    result = continue(Account, :withdraw, [account, amount])
    IO.puts("new balance: #{result.balance}")
    result
  end

  defpartial Account.withdraw(_account, _amount, _ctx), mode: :after do
    IO.puts("withdrawal complete")
  end
end
```

Supported partial modes:

| Mode | Description |
| --- | --- |
| `:around` | Wraps the next layer or primary function. Call `continue/3` to proceed. |
| `:before` | Runs before the primary function. |
| `:after` | Runs after the primary function returns. |

An `:around` partial may short-circuit the call by not calling `continue/3`.

### Dynamic Activation

Activate layers for a single call with `Contexir.with_layers/2`:

```elixir
require Contexir

Contexir.with_layers(
  [LoggingLayer],
  Account.withdraw(%{balance: 100}, 25, %{})
)
```

Layer activation and context are process-local. They do not automatically cross
`spawn`, `Task.async`, or other BEAM process boundaries.

## Execution Order

For active layers `[A, B]`, dispatch follows this order:

```text
A around
  B around
    A before
    B before
      primary
    B after
    A after
  B around end
A around end
```

`:after` partials run inside-out, after the primary function returns.

## Layer Composition

Layers can include other layers:

```elixir
deflayer SecureLayer do
  use_layers([Authentication, Audit])
end
```

Layers can also declare composition relationships:

```elixir
deflayer SecureCheckout do
  requires(Authentication)
  conflicts_with(GuestCheckout)
  before(Audit)
  after_layer(RateLimit)
end
```

`requires` and `conflicts_with` are validated by `Contexir.Layer.resolve/1` and
before activation through `Contexir.with_layers/2`.

```elixir
Contexir.Layer.resolve([Authentication, SecureCheckout, Audit])
#=> {:ok, [Authentication, SecureCheckout, Audit]}
```

`before` and `after_layer` are recorded as metadata and reserved for precedence
ordering. Runtime ordering from those relationships is not implemented yet.

## Layer Introspection

Use `Contexir.Layer.info/1` to inspect layer metadata:

```elixir
Contexir.Layer.info(SecureCheckout)
#=> %{
#=>   module: SecureCheckout,
#=>   partials: [...],
#=>   includes: [],
#=>   requires: [Authentication],
#=>   conflicts_with: [GuestCheckout],
#=>   before: [Audit],
#=>   after: [RateLimit],
#=>   predicate?: false
#=> }
```

## Declarative Context Activation

Use `defcontext` to select layers from context values:

```elixir
defcontext CheckoutContext do
  layer(Authentication, when: & &1[:user])
  layer(Audit, when: & &1[:audit?])
  layer(FraudReview, when: &(&1[:risk_score] >= 70))
end
```

Then dispatch with layers selected from the context:

```elixir
Contexir.with_context(
  CheckoutContext,
  %{user: "alice", audit?: true, risk_score: 82},
  Checkout.submit(cart, %{})
)
```

The provided context replaces the final argument of the target call.

## Context API

`Contexir.Context` exposes helpers for process-local context:

```elixir
Contexir.Context.with_context(%{request_id: "req-123"}, fn ->
  Contexir.Context.get(:request_id)
  Contexir.Context.put(:user, "alice")
  Contexir.Context.update(:attempts, 1, &(&1 + 1))
  Contexir.Context.current()
end)
```

For lower-level scope work, `Contexir.Context.with_scope/3` temporarily installs
both active layers and context.

## Task Propagation

Plain BEAM tasks do not inherit Contexir state. Use `Contexir.Task` when a task
should run with the caller's current active layers and context:

```elixir
Contexir.Context.with_scope([TraceLayer], %{request_id: "req-123"}, fn ->
  task =
    Contexir.Task.async(fn ->
      Contexir.with_layers(
        [],
        Worker.run("job", Contexir.Context.current())
      )
    end)

  Contexir.Task.await(task)
end)
```

`Contexir.Task.async/1` wraps Elixir's linked `Task.async/1`.

## Examples

The `examples/` directory contains runnable scripts:

```bash
mix run examples/basic_layers.exs
mix run examples/composition_resolution.exs
mix run examples/declarative_context.exs
mix run examples/task_propagation.exs
mix run examples/checkout_flow.exs
```

`examples/checkout_flow.exs` is the most complete example. It combines
declarative context rules, composition validation, layered dispatch, context
updates, and task propagation.

## Current Limitations

* `before` and `after_layer` relationships are metadata only; precedence
  ordering and cycle detection are not implemented yet.
* Context and active layers are process-local. Use `Contexir.Task` for explicit
  task propagation.
* `Contexir.explain` and telemetry integration are not implemented yet.

## License

Unlicense

## Learn More

* [Context-Oriented Programming](https://en.wikipedia.org/wiki/Context-oriented_programming)
* [Aspect-Oriented Programming](https://en.wikipedia.org/wiki/Aspect-oriented_programming)
