# Contexir

![contexir](https://raw.githubusercontent.com/diasbruno/contexir/refs/heads/development/assets/contexir.png "contexir")

> 🧠 Context-Oriented Programming for Elixir — composable layers for dynamic, context-aware behavior.

**Contexir** brings *Context-Oriented Programming (COP)* semantics to Elixir.
It lets you define **layers** that dynamically refine how your modules behave,
based on runtime context — without modifying the original code.

---

## ✨ Features

- 🧩 **Layered Behavior** — define context-sensitive extensions for existing functions.
- 🪞 **Execution Plan** — predictable order of execution (`around`, `before`, `after`).
- ⚙️ **Composable Layers** — group and reuse layers (`use_layers`).
- 🧠 **Dynamic Activation** — activate layers with `Contexir.with_layers/2`.
- 💡 **Pure Functional Design** — no global mutation, fully scoped per process.
- 🧰 **Simple API** — use regular Elixir syntax; no complex macros required.

---

## 🚀 Installation

Add **Contexir** to your `mix.exs`:

```elixir
def deps do
  [
    {:contexir, github: "diasbruno/contexir"}
  ]
end
````

Then fetch the dependency:

```bash
mix deps.get
```

---

## 🧩 Basic Example

```elixir
defmodule Account do
  use Contexir.Base

  def withdraw(acc, amt, _ctx) do
    IO.puts("primary")
    %{acc | balance: acc.balance - amt}
  end
end

deflayer LoggingLayer do
  defpartial Account.withdraw(acc, amt, ctx), mode: :before do
    IO.puts("[BEFORE] Logging withdrawal of #{amt}")
  end

  defpartial Account.withdraw(acc, amt, ctx), mode: :around do
    IO.puts("[AROUND] Starting transaction")
    result = continue(Account, :withdraw, [acc, amt, ctx])
    IO.puts("[AROUND] Finished transaction")
    result
  end

  defpartial Account.withdraw(_acc, _amt, _ctx), mode: :after do
    IO.puts("[AFTER] Done.")
  end
end

Contexir.with_layers [LoggingLayer] do
  Account.withdraw(%{balance: 1000}, 100, %{})
end
```

**Output:**

```
[AROUND] Starting transaction
[BEFORE] Logging withdrawal of 100
primary
[AFTER] Done.
[AROUND] Finished transaction
```

---

## 🧭 Execution Model

When multiple layers are active, the execution order follows this pattern:

| Mode        | Direction     | Description                                                 |
| ----------- | ------------- | ----------------------------------------------------------- |
| **around**  | outer → inner | Each `around` wraps the next layer. Must call `continue/3`. |
| **before**  | outer → inner | Runs before the primary function.                           |
| **primary** | —             | The original function being refined.                        |
| **after**   | inner → outer | Runs after the primary returns.                             |

Example for `[A, B]` active layers:

```
A:around
B:around
A:before
B:before
primary
B:after
A:after
B:around end
A:around end
```

---

## ⚙️ Layer Composition

Layers can include other layers:

```elixir
deflayer SecureLayer do
  use_layers [AuthLayer, LoggingLayer]
end

Contexir.with_layers [SecureLayer] do
  # Equivalent to activating both AuthLayer and LoggingLayer
end
```

---

## 💡 Why Context-Oriented Programming?

Traditional OOP or FP decomposition struggles with **runtime behavioral variation** —
when behavior must adapt to *context* (e.g., user role, request origin, environment).

COP solves this by:

* Separating *context-dependent* behavior into **layers**.
* Activating those layers dynamically, without polluting core logic.
* Allowing clean, composable runtime adaptation.

Contexir brings these ideas to Elixir — leveraging the BEAM’s process isolation and pure data flow.

---

## 📦 Project Goals

* Keep the model **simple and functional**.
* Serve as a foundation for **runtime adaptation libraries** in Elixir.
* Explore **dynamic system composition** patterns (adaptive services, domain-specific contexts, etc.).

---

## 🧰 Roadmap

* [ ] Layer predicates for context-based activation
* [ ] Layer priorities
* [ ] Async execution (experimental)
* [ ] Debug/tracing integration

---

## 📄 License

Unlicense

---

## 🧠 Learn More

* [Context-Oriented Programming (Wikipedia)](https://en.wikipedia.org/wiki/Context-oriented_programming)
* [Lisp COP model](https://dl.acm.org/doi/10.1145/1330511.1330517)
* [Aspect-Oriented Programming](https://en.wikipedia.org/wiki/Aspect-oriented_programming)
