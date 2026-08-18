import Contexir.Layer

# Composition metadata lets a layer describe which other layers it needs and
# which combinations must be rejected before dispatch begins.

deflayer Examples.Composition.Authentication do
end

deflayer Examples.Composition.Audit do
end

deflayer Examples.Composition.SecureCheckout do
  requires(Examples.Composition.Authentication)
  conflicts_with(Examples.Composition.GuestCheckout)

  # Precedence relationships are exposed as metadata today. They are useful for
  # introspection, but Contexir does not reorder layers from before/after yet.
  before(Examples.Composition.Audit)
end

deflayer Examples.Composition.GuestCheckout do
end

IO.inspect(
  Contexir.Layer.resolve([
    Examples.Composition.Authentication,
    Examples.Composition.SecureCheckout,
    Examples.Composition.Audit
  ]),
  label: "valid composition"
)

# GuestCheckout conflicts with SecureCheckout, so resolution returns an error
# instead of an execution plan.
IO.inspect(
  Contexir.Layer.resolve([
    Examples.Composition.Authentication,
    Examples.Composition.SecureCheckout,
    Examples.Composition.GuestCheckout
  ]),
  label: "invalid composition"
)
