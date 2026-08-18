import Contexir.Layer
require Contexir

defmodule Examples.DeclarativeContext.Page do
  use Contexir

  def render(page, _ctx) do
    page
  end
end

deflayer Examples.DeclarativeContext.Mobile do
  defpartial Examples.DeclarativeContext.Page.render(page, _ctx), mode: :around do
    continue(
      Examples.DeclarativeContext.Page,
      :render,
      [%{page | layout: :mobile}]
    )
  end
end

deflayer Examples.DeclarativeContext.LowBattery do
  defpartial Examples.DeclarativeContext.Page.render(page, _ctx), mode: :around do
    continue(
      Examples.DeclarativeContext.Page,
      :render,
      [%{page | effects: :reduced}]
    )
  end
end

defcontext Examples.DeclarativeContext.AppContext do
  layer(Examples.DeclarativeContext.Mobile, when: &(&1.network == :cellular))
  layer(Examples.DeclarativeContext.LowBattery, when: &(&1.battery < 20))
end

page =
  Contexir.with_context(
    Examples.DeclarativeContext.AppContext,
    %{network: :cellular, battery: 10},
    Examples.DeclarativeContext.Page.render(%{layout: :desktop, effects: :full}, %{})
  )

IO.inspect(page, label: "context-aware page")

page =
  Contexir.with_context(
    Examples.DeclarativeContext.AppContext,
    %{network: :cellular, battery: 30},
    Examples.DeclarativeContext.Page.render(%{layout: :desktop, effects: :full}, %{})
  )

IO.inspect(page, label: "context-aware page")

page =
  Contexir.with_context(
    Examples.DeclarativeContext.AppContext,
    %{network: :wifi, battery: 30},
    Examples.DeclarativeContext.Page.render(%{layout: :desktop, effects: :full}, %{})
  )

IO.inspect(page, label: "context-aware page")
