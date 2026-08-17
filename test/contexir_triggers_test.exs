defmodule ContexirTriggersTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  defmodule Target do
    use Contexir

    def execute(acc, ctx) do
      %{acc | string: acc.string <> " target_part"}
    end

    def ordered(acc, ctx) do
      log("primary")
      acc
    end

    def log(entry) do
      Process.put(:contexir_order, Process.get(:contexir_order, []) ++ [entry])
    end

    def active_layers(_acc, _ctx) do
      Contexir.Context.active_layers()
    end
  end

  deflayer BeforeAfter do
    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :around do
      %{string: s} = acc

      continue(
        ContexirTriggersTest.Target,
        :execute,
        [%{string: s <> " around before-after_part"}]
      )
    end

    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :before do
      Process.put(:target, 1)
    end

    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :after do
      x = Process.get(:target) || 0
      Process.put(:target, x - 1)
    end
  end

  deflayer Outer do
    defpartial ContexirTriggersTest.Target.ordered(acc, ctx), mode: :around do
      ContexirTriggersTest.Target.log("A around")

      result =
        continue(
          ContexirTriggersTest.Target,
          :ordered,
          [acc]
        )

      ContexirTriggersTest.Target.log("A around end")
      result
    end

    defpartial ContexirTriggersTest.Target.ordered(acc, ctx), mode: :before do
      ContexirTriggersTest.Target.log("A before")
    end

    defpartial ContexirTriggersTest.Target.ordered(acc, ctx), mode: :after do
      ContexirTriggersTest.Target.log("A after")
    end
  end

  deflayer Inner do
    defpartial ContexirTriggersTest.Target.ordered(acc, ctx), mode: :around do
      ContexirTriggersTest.Target.log("B around")

      result =
        continue(
          ContexirTriggersTest.Target,
          :ordered,
          [acc]
        )

      ContexirTriggersTest.Target.log("B around end")
      result
    end

    defpartial ContexirTriggersTest.Target.ordered(acc, ctx), mode: :before do
      ContexirTriggersTest.Target.log("B before")
    end

    defpartial ContexirTriggersTest.Target.ordered(acc, ctx), mode: :after do
      ContexirTriggersTest.Target.log("B after")
    end
  end

  deflayer ActivationProbe do
    defpartial ContexirTriggersTest.Target.active_layers(acc, ctx), mode: :around do
      continue(
        ContexirTriggersTest.Target,
        :active_layers,
        [acc]
      )
    end
  end

  #
  # Tests
  #

  # @tag :skip
  test "run before/after layer" do
    layers = [ContexirTriggersTest.BeforeAfter]

    %{string: b} =
      Contexir.with_layers(
        layers,
        ContexirTriggersTest.Target.execute(%{string: "start_string"}, %{user: "Alice"})
      )

    x = Process.get(:target)
    assert x == 0
    assert b == "start_string around before-after_part target_part"
  end

  test "runs around before primary after in layer order" do
    Process.delete(:contexir_order)
    layers = [ContexirTriggersTest.Outer, ContexirTriggersTest.Inner]

    Contexir.with_layers(
      layers,
      ContexirTriggersTest.Target.ordered(%{}, %{})
    )

    assert Process.get(:contexir_order) == [
             "A around",
             "B around",
             "A before",
             "B before",
             "primary",
             "B after",
             "A after",
             "B around end",
             "A around end"
           ]
  end

  test "keeps activation layers separate from dispatch execution state" do
    layers = [ContexirTriggersTest.ActivationProbe]

    assert Contexir.with_layers(
             layers,
             ContexirTriggersTest.Target.active_layers(%{}, %{})
           ) == layers
  end
end
