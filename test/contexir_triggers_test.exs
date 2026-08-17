defmodule ContexirTriggersTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  defmodule Target do
    use Contexir

    def execute(acc, _ctx) do
      %{acc | string: acc.string <> " target_part"}
    end

    def ordered(acc, _ctx) do
      log("primary")
      acc
    end

    def log(entry) do
      Process.put(:contexir_order, Process.get(:contexir_order, []) ++ [entry])
    end

    def active_layers(_acc, _ctx) do
      Contexir.Context.active_layers()
    end

    def parent(acc, _ctx) do
      log("parent primary #{Contexir.Context.get_ctx().request_id}")
      acc
    end

    def child(acc, _ctx) do
      log("child primary #{Contexir.Context.get_ctx().request_id}")
      acc
    end

    def parent_after_exception(acc, _ctx) do
      log("parent exception primary #{Contexir.Context.get_ctx().request_id}")
      acc
    end

    def failing_child(_acc, _ctx) do
      log("failing child primary #{Contexir.Context.get_ctx().request_id}")
      raise "nested failure"
    end
  end

  deflayer BeforeAfter do
    defpartial ContexirTriggersTest.Target.execute(acc, _ctx), mode: :around do
      %{string: s} = acc

      continue(
        ContexirTriggersTest.Target,
        :execute,
        [%{string: s <> " around before-after_part"}]
      )
    end

    defpartial ContexirTriggersTest.Target.execute(_acc, _ctx), mode: :before do
      Process.put(:target, 1)
    end

    defpartial ContexirTriggersTest.Target.execute(_acc, _ctx), mode: :after do
      x = Process.get(:target) || 0
      Process.put(:target, x - 1)
    end
  end

  deflayer Outer do
    defpartial ContexirTriggersTest.Target.ordered(acc, _ctx), mode: :around do
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

    defpartial ContexirTriggersTest.Target.ordered(_acc, _ctx), mode: :before do
      ContexirTriggersTest.Target.log("A before")
    end

    defpartial ContexirTriggersTest.Target.ordered(_acc, _ctx), mode: :after do
      ContexirTriggersTest.Target.log("A after")
    end
  end

  deflayer Inner do
    defpartial ContexirTriggersTest.Target.ordered(acc, _ctx), mode: :around do
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

    defpartial ContexirTriggersTest.Target.ordered(_acc, _ctx), mode: :before do
      ContexirTriggersTest.Target.log("B before")
    end

    defpartial ContexirTriggersTest.Target.ordered(_acc, _ctx), mode: :after do
      ContexirTriggersTest.Target.log("B after")
    end
  end

  deflayer ActivationProbe do
    defpartial ContexirTriggersTest.Target.active_layers(acc, _ctx), mode: :around do
      continue(
        ContexirTriggersTest.Target,
        :active_layers,
        [acc]
      )
    end
  end

  deflayer ParentDispatch do
    defpartial ContexirTriggersTest.Target.parent(acc, _ctx), mode: :around do
      ContexirTriggersTest.Target.log("parent around #{Contexir.Context.get_ctx().request_id}")

      Contexir.with_layers(
        [],
        ContexirTriggersTest.Target.child(acc, %{request_id: :child})
      )

      ContexirTriggersTest.Target.log(
        "parent after nested #{Contexir.Context.get_ctx().request_id}"
      )

      continue(
        ContexirTriggersTest.Target,
        :parent,
        [acc]
      )
    end
  end

  deflayer ChildDispatch do
    defpartial ContexirTriggersTest.Target.child(acc, _ctx), mode: :around do
      ContexirTriggersTest.Target.log("child around #{Contexir.Context.get_ctx().request_id}")

      continue(
        ContexirTriggersTest.Target,
        :child,
        [acc]
      )
    end
  end

  deflayer ParentRescuesDispatch do
    defpartial ContexirTriggersTest.Target.parent_after_exception(acc, _ctx), mode: :around do
      ContexirTriggersTest.Target.log(
        "parent exception around #{Contexir.Context.get_ctx().request_id}"
      )

      try do
        Contexir.with_layers(
          [],
          ContexirTriggersTest.Target.failing_child(acc, %{request_id: :child})
        )
      rescue
        RuntimeError ->
          ContexirTriggersTest.Target.log(
            "parent rescued #{Contexir.Context.get_ctx().request_id}"
          )
      end

      continue(
        ContexirTriggersTest.Target,
        :parent_after_exception,
        [acc]
      )
    end
  end

  deflayer FailingChildDispatch do
    defpartial ContexirTriggersTest.Target.failing_child(acc, _ctx), mode: :around do
      ContexirTriggersTest.Target.log(
        "failing child around #{Contexir.Context.get_ctx().request_id}"
      )

      continue(
        ContexirTriggersTest.Target,
        :failing_child,
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

  test "nested dispatch gets its own execution state and restores parent context" do
    Process.delete(:contexir_order)

    Contexir.with_layers(
      [ContexirTriggersTest.ParentDispatch, ContexirTriggersTest.ChildDispatch],
      ContexirTriggersTest.Target.parent(%{}, %{request_id: :parent})
    )

    assert Process.get(:contexir_order) == [
             "parent around parent",
             "child around child",
             "child primary child",
             "parent after nested parent",
             "parent primary parent"
           ]
  end

  test "nested dispatch restores parent execution state after exception" do
    Process.delete(:contexir_order)

    Contexir.with_layers(
      [ContexirTriggersTest.ParentRescuesDispatch, ContexirTriggersTest.FailingChildDispatch],
      ContexirTriggersTest.Target.parent_after_exception(%{}, %{request_id: :parent})
    )

    assert Process.get(:contexir_order) == [
             "parent exception around parent",
             "failing child around child",
             "failing child primary child",
             "parent rescued parent",
             "parent exception primary parent"
           ]
  end
end
