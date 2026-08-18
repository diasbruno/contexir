import Contexir.Layer

deflayer Examples.Composition.Authentication do
end

deflayer Examples.Composition.Audit do
end

deflayer Examples.Composition.SecureCheckout do
  requires(Examples.Composition.Authentication)
  conflicts_with(Examples.Composition.GuestCheckout)
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

IO.inspect(
  Contexir.Layer.resolve([
    Examples.Composition.Authentication,
    Examples.Composition.SecureCheckout,
    Examples.Composition.GuestCheckout
  ]),
  label: "invalid composition"
)
