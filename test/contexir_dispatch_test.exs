defmodule ContexirDispatchTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  defmodule Target do
    use Contexir

    def execute(acc, _ctx), do: %{acc | string: acc.string <> " target"}

    def ordered(acc, _ctx) do
      log("primary")
      acc
    end

    def active_layers(_acc, _ctx), do: Contexir.Context.active_layers()

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

    def short_circuit(acc, _ctx) do
      log("short primary")
      acc
    end

    def log(entry) do
      Process.put(:contexir_order, Process.get(:contexir_order, []) ++ [entry])
    end
  end

  deflayer BeforeAfter do
    defpartial ContexirDispatchTest.Target.execute(acc, _ctx), mode: :around do
      %{string: string} = acc

      continue(
        ContexirDispatchTest.Target,
        :execute,
        [%{string: string <> " around"}]
      )
    end

    defpartial ContexirDispatchTest.Target.execute(_acc, _ctx), mode: :before do
      Process.put(:target, 1)
    end

    defpartial ContexirDispatchTest.Target.execute(_acc, _ctx), mode: :after do
      Process.put(:target, (Process.get(:target) || 0) - 1)
    end
  end

  deflayer PredicateAroundLayer, when: fn _mod, _fun, _args, ctx -> ctx[:enabled] end do
    defpartial ContexirDispatchTest.Target.execute(acc, _ctx), mode: :around do
      %{string: string} = acc

      continue(
        ContexirDispatchTest.Target,
        :execute,
        [%{string: string <> " predicate"}]
      )
    end
  end

  deflayer Outer do
    defpartial ContexirDispatchTest.Target.ordered(acc, _ctx), mode: :around do
      ContexirDispatchTest.Target.log("A around")

      result =
        continue(
          ContexirDispatchTest.Target,
          :ordered,
          [acc]
        )

      ContexirDispatchTest.Target.log("A around end")
      result
    end

    defpartial ContexirDispatchTest.Target.ordered(_acc, _ctx), mode: :before do
      ContexirDispatchTest.Target.log("A before")
    end

    defpartial ContexirDispatchTest.Target.ordered(_acc, _ctx), mode: :after do
      ContexirDispatchTest.Target.log("A after")
    end
  end

  deflayer Inner do
    defpartial ContexirDispatchTest.Target.ordered(acc, _ctx), mode: :around do
      ContexirDispatchTest.Target.log("B around")

      result =
        continue(
          ContexirDispatchTest.Target,
          :ordered,
          [acc]
        )

      ContexirDispatchTest.Target.log("B around end")
      result
    end

    defpartial ContexirDispatchTest.Target.ordered(_acc, _ctx), mode: :before do
      ContexirDispatchTest.Target.log("B before")
    end

    defpartial ContexirDispatchTest.Target.ordered(_acc, _ctx), mode: :after do
      ContexirDispatchTest.Target.log("B after")
    end
  end

  deflayer ActivationProbe do
    defpartial ContexirDispatchTest.Target.active_layers(acc, _ctx), mode: :around do
      continue(
        ContexirDispatchTest.Target,
        :active_layers,
        [acc]
      )
    end
  end

  deflayer ParentDispatch do
    defpartial ContexirDispatchTest.Target.parent(acc, _ctx), mode: :around do
      ContexirDispatchTest.Target.log("parent around #{Contexir.Context.get_ctx().request_id}")

      Contexir.with_layers(
        [],
        ContexirDispatchTest.Target.child(acc, %{request_id: :child})
      )

      ContexirDispatchTest.Target.log(
        "parent after nested #{Contexir.Context.get_ctx().request_id}"
      )

      continue(
        ContexirDispatchTest.Target,
        :parent,
        [acc]
      )
    end
  end

  deflayer ChildDispatch do
    defpartial ContexirDispatchTest.Target.child(acc, _ctx), mode: :around do
      ContexirDispatchTest.Target.log("child around #{Contexir.Context.get_ctx().request_id}")

      continue(
        ContexirDispatchTest.Target,
        :child,
        [acc]
      )
    end
  end

  deflayer ParentRescuesDispatch do
    defpartial ContexirDispatchTest.Target.parent_after_exception(acc, _ctx), mode: :around do
      ContexirDispatchTest.Target.log(
        "parent exception around #{Contexir.Context.get_ctx().request_id}"
      )

      try do
        Contexir.with_layers(
          [],
          ContexirDispatchTest.Target.failing_child(acc, %{request_id: :child})
        )
      rescue
        RuntimeError ->
          ContexirDispatchTest.Target.log(
            "parent rescued #{Contexir.Context.get_ctx().request_id}"
          )
      end

      continue(
        ContexirDispatchTest.Target,
        :parent_after_exception,
        [acc]
      )
    end
  end

  deflayer FailingChildDispatch do
    defpartial ContexirDispatchTest.Target.failing_child(acc, _ctx), mode: :around do
      ContexirDispatchTest.Target.log(
        "failing child around #{Contexir.Context.get_ctx().request_id}"
      )

      continue(
        ContexirDispatchTest.Target,
        :failing_child,
        [acc]
      )
    end
  end

  deflayer ShortCircuitLayer do
    defpartial ContexirDispatchTest.Target.short_circuit(acc, _ctx), mode: :around do
      ContexirDispatchTest.Target.log("short around")
      %{acc | string: acc.string <> " captured"}
    end

    defpartial ContexirDispatchTest.Target.short_circuit(_acc, _ctx), mode: :before do
      ContexirDispatchTest.Target.log("short before")
    end

    defpartial ContexirDispatchTest.Target.short_circuit(_acc, _ctx), mode: :after do
      ContexirDispatchTest.Target.log("short after")
    end
  end

  test "runs before and after partials" do
    %{string: string} =
      Contexir.with_layers(
        [ContexirDispatchTest.BeforeAfter],
        ContexirDispatchTest.Target.execute(%{string: "start"}, %{})
      )

    assert Process.get(:target) == 0
    assert string == "start around target"
  end

  test "predicate layers activate only when predicate matches context" do
    %{string: active} =
      Contexir.with_layers(
        [ContexirDispatchTest.PredicateAroundLayer],
        ContexirDispatchTest.Target.execute(%{string: "start"}, %{enabled: true})
      )

    %{string: inactive} =
      Contexir.with_layers(
        [ContexirDispatchTest.PredicateAroundLayer],
        ContexirDispatchTest.Target.execute(%{string: "start"}, %{enabled: false})
      )

    assert active == "start predicate target"
    assert inactive == "start target"
  end

  test "around partial can short-circuit without before after or primary" do
    Process.delete(:contexir_order)

    assert Contexir.with_layers(
             [ContexirDispatchTest.ShortCircuitLayer],
             ContexirDispatchTest.Target.short_circuit(%{string: "start"}, %{})
           ) == %{string: "start captured"}

    assert Process.get(:contexir_order) == ["short around"]
  end

  test "runs around before primary after in layer order" do
    Process.delete(:contexir_order)

    Contexir.with_layers(
      [ContexirDispatchTest.Outer, ContexirDispatchTest.Inner],
      ContexirDispatchTest.Target.ordered(%{}, %{})
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
    layers = [ContexirDispatchTest.ActivationProbe]

    assert Contexir.with_layers(
             layers,
             ContexirDispatchTest.Target.active_layers(%{}, %{})
           ) == layers
  end

  test "nested dispatch gets its own execution state and restores parent context" do
    Process.delete(:contexir_order)

    Contexir.with_layers(
      [ContexirDispatchTest.ParentDispatch, ContexirDispatchTest.ChildDispatch],
      ContexirDispatchTest.Target.parent(%{}, %{request_id: :parent})
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
      [ContexirDispatchTest.ParentRescuesDispatch, ContexirDispatchTest.FailingChildDispatch],
      ContexirDispatchTest.Target.parent_after_exception(%{}, %{request_id: :parent})
    )

    assert Process.get(:contexir_order) == [
             "parent exception around parent",
             "failing child around child",
             "failing child primary child",
             "parent rescued parent",
             "parent exception primary parent"
           ]
  end

  test "activate and deactivate update active layers" do
    try do
      Contexir.Context.activate(ContexirDispatchTest.Outer)
      Contexir.Context.activate(ContexirDispatchTest.Inner)

      assert Contexir.Context.active_layers() == [
               ContexirDispatchTest.Inner,
               ContexirDispatchTest.Outer
             ]

      Contexir.Context.deactivate(ContexirDispatchTest.Inner)

      assert Contexir.Context.active_layers() == [ContexirDispatchTest.Outer]
    after
      Contexir.Context.deactivate(ContexirDispatchTest.Inner)
      Contexir.Context.deactivate(ContexirDispatchTest.Outer)
    end
  end
end
