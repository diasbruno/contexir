import Contexir.Layer
require Contexir

# This example keeps checkout's core rule deliberately ordinary: calculate the
# final cart from the cart data. The surrounding layers add request-specific
# behavior such as authentication, loyalty discounts, fraud checks, audit
# messages, and task propagation.

defmodule Examples.CheckoutFlow.Checkout do
  use Contexir

  def submit(cart, _ctx) do
    total =
      cart
      |> subtotal()
      |> apply_discount(cart.discount)
      |> apply_shipping(cart.shipping)

    %{cart | total: total}
    |> append("primary: charge #{format_money(total)}")
  end

  defp append(cart, event), do: %{cart | events: cart.events ++ [event]}
  defp subtotal(cart), do: Enum.reduce(cart.items, 0, &(&2 + &1.price))
  defp apply_discount(total, discount), do: max(total - discount, 0)
  defp apply_shipping(total, shipping), do: total + shipping
  defp format_money(amount), do: "$#{:erlang.float_to_binary(amount / 1, decimals: 2)}"
end

deflayer Examples.CheckoutFlow.Authentication do
  # :before partials are useful for validation or context enrichment. Here the
  # layer records that downstream layers can treat the request as authenticated.
  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :before do
    Contexir.Context.put(:authenticated?, true)
    send(cart.audit_pid, "before: authenticated #{Contexir.Context.get(:user)}")
  end
end

deflayer Examples.CheckoutFlow.LoyaltyDiscount do
  requires(Examples.CheckoutFlow.Authentication)

  # :around partials can alter the arguments before the primary function runs.
  # continue/3 receives only the business arguments; Contexir carries the
  # current context separately.
  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :around do
    discount = 10
    Contexir.Context.put(:loyalty_discount, discount)
    send(cart.audit_pid, "around: loyalty discount applied")

    continue(
      Examples.CheckoutFlow.Checkout,
      :submit,
      [%{cart | discount: cart.discount + discount}]
    )
  end
end

deflayer Examples.CheckoutFlow.Audit do
  # Audit wraps the rest of the call, so it can emit messages before and after
  # the primary checkout calculation and all inner around partials.
  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :around do
    send(cart.audit_pid, "around: audit start #{Contexir.Context.get(:request_id)}")

    result =
      continue(
        Examples.CheckoutFlow.Checkout,
        :submit,
        [%{cart | events: cart.events ++ ["around: audit start"]}]
      )

    send(cart.audit_pid, "around: audit end #{Contexir.Context.get(:request_id)}")
    %{result | events: result.events ++ ["around: audit end"]}
  end

  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :after do
    send(cart.audit_pid, "after: audit recorded")
  end
end

deflayer Examples.CheckoutFlow.FreeShipping do
  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :around do
    continue(
      Examples.CheckoutFlow.Checkout,
      :submit,
      [%{cart | shipping: 0, events: cart.events ++ ["around: free shipping"]}]
    )
  end
end

deflayer Examples.CheckoutFlow.PriorityCheckout do
  requires(Examples.CheckoutFlow.Authentication)
  conflicts_with(Examples.CheckoutFlow.GuestCheckout)

  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :around do
    continue(
      Examples.CheckoutFlow.Checkout,
      :submit,
      [%{cart | events: cart.events ++ ["around: priority checkout"]}]
    )
  end
end

deflayer Examples.CheckoutFlow.FraudReview do
  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :before do
    send(cart.audit_pid, "before: fraud review #{Contexir.Context.get(:risk_score)}")
  end
end

deflayer Examples.CheckoutFlow.ManualApproval do
  requires(Examples.CheckoutFlow.FraudReview)

  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :before do
    send(cart.audit_pid, "before: manual approval required")
  end
end

deflayer Examples.CheckoutFlow.GuestCheckout do
  defpartial Examples.CheckoutFlow.Checkout.submit(cart, _ctx), mode: :around do
    continue(
      Examples.CheckoutFlow.Checkout,
      :submit,
      [%{cart | events: cart.events ++ ["around: guest checkout"]}]
    )
  end
end

defcontext Examples.CheckoutFlow.RequestContext do
  # Context rules translate request data into layers. Composition validation then
  # checks requirements and conflicts before any checkout code runs.
  layer(Examples.CheckoutFlow.Authentication, when: & &1[:user])
  layer(Examples.CheckoutFlow.GuestCheckout, when: &is_nil(&1[:user]))
  layer(Examples.CheckoutFlow.Audit, when: & &1[:audit?])
  layer(Examples.CheckoutFlow.LoyaltyDiscount, when: &(&1[:customer_tier] in [:gold, :vip]))
  layer(Examples.CheckoutFlow.FreeShipping, when: &(&1[:subtotal] >= 50))
  layer(Examples.CheckoutFlow.PriorityCheckout, when: &(&1[:customer_tier] == :vip))
  layer(Examples.CheckoutFlow.FraudReview, when: &(&1[:risk_score] >= 70))
  layer(Examples.CheckoutFlow.ManualApproval, when: &(&1[:risk_score] >= 90))
end

scenarios = %{
  "1" => %{
    name: "VIP customer with audit and fraud review",
    context: %{
      request_id: "checkout-vip-123",
      user: "alice",
      audit?: true,
      customer_tier: :vip,
      risk_score: 82
    },
    items: [
      %{name: "Coffee grinder", price: 42},
      %{name: "Filters", price: 12}
    ]
  },
  "2" => %{
    name: "Gold customer with free shipping",
    context: %{
      request_id: "checkout-gold-456",
      user: "bruno",
      audit?: true,
      customer_tier: :gold,
      risk_score: 20
    },
    items: [
      %{name: "Keyboard", price: 72}
    ]
  },
  "3" => %{
    name: "Guest checkout",
    context: %{
      request_id: "checkout-guest-789",
      user: nil,
      audit?: false,
      customer_tier: :guest,
      risk_score: 10
    },
    items: [
      %{name: "Notebook", price: 18}
    ]
  },
  "4" => %{
    name: "High-risk VIP requiring manual approval",
    context: %{
      request_id: "checkout-review-999",
      user: "carol",
      audit?: true,
      customer_tier: :vip,
      risk_score: 95
    },
    items: [
      %{name: "Camera", price: 180},
      %{name: "Lens", price: 220}
    ]
  }
}

IO.puts("Choose a checkout scenario:")

Enum.each(scenarios, fn {key, scenario} ->
  IO.puts("  #{key}. #{scenario.name}")
end)

choice =
  IO.gets("\nScenario [1]: ")
  |> case do
    :eof -> "1"
    input -> input |> String.trim() |> then(&if(&1 == "", do: "1", else: &1))
  end

scenario = Map.get(scenarios, choice, scenarios["1"])

subtotal = Enum.sum(Enum.map(scenario.items, & &1.price))
context = Map.put(scenario.context, :subtotal, subtotal)

# resolve_context!/2 performs two steps:
#
#   * it evaluates each RequestContext rule against the request-shaped context;
#   * it resolves the resulting layers, expanding includes and rejecting missing
#     requirements or conflicts before the checkout task starts.
#
# For example, the VIP scenario activates Authentication, LoyaltyDiscount,
# FreeShipping, PriorityCheckout, FraudReview, and Audit from plain request data.
layers = Contexir.Layer.resolve_context!(Examples.CheckoutFlow.RequestContext, context)

IO.puts("\nscenario:")
IO.puts("  #{scenario.name}")

IO.puts("\nitems:")
Enum.each(scenario.items, &IO.puts("  #{&1.name}: $#{&1.price}"))

IO.puts("\nresolved layers:")
Enum.each(layers, &IO.puts("  #{inspect(&1)}"))

cart = %{
  items: scenario.items,
  discount: 0,
  shipping: 7,
  total: 0,
  events: [],
  audit_pid: self()
}

task =
  Contexir.Context.with_scope(layers, context, fn ->
    # The checkout work runs in another process, but Contexir.Task preserves the
    # scope selected above.
    Contexir.Task.async(fn ->
      Contexir.with_layers(
        [],
        Examples.CheckoutFlow.Checkout.submit(cart, Contexir.Context.current())
      )
    end)
  end)

result = Contexir.Task.await(task)

IO.puts("\ncheckout events:")
Enum.each(result.events, &IO.puts("  #{&1}"))

IO.puts("\nfinal cart:")
IO.puts("  discount: $#{result.discount}")
IO.puts("  shipping: $#{result.shipping}")
IO.puts("  total: $#{:erlang.float_to_binary(result.total / 1, decimals: 2)}")

IO.puts("\naudit messages:")

for _ <- 1..8 do
  receive do
    message -> IO.puts("  #{message}")
  after
    100 -> :ok
  end
end
