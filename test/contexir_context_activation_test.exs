defmodule ContexirContextActivationTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  defmodule Target do
    use Contexir

    def read(_acc, _ctx) do
      Contexir.Context.current()
    end

    def execute(acc, _ctx) do
      %{acc | string: acc.string <> " target"}
    end
  end

  deflayer MobileLayer do
    defpartial ContexirContextActivationTest.Target.execute(acc, _ctx), mode: :around do
      continue(
        ContexirContextActivationTest.Target,
        :execute,
        [%{acc | string: acc.string <> " mobile"}]
      )
    end
  end

  deflayer LowBatteryLayer do
    defpartial ContexirContextActivationTest.Target.execute(acc, _ctx), mode: :around do
      continue(
        ContexirContextActivationTest.Target,
        :execute,
        [%{acc | string: acc.string <> " battery"}]
      )
    end
  end

  deflayer RequiresMobileLayer do
    requires(ContexirContextActivationTest.MobileLayer)
  end

  defcontext ApplicationContext do
    layer(ContexirContextActivationTest.MobileLayer, when: &(&1.network == :cellular))
    layer(ContexirContextActivationTest.LowBatteryLayer, when: &(&1.battery < 20))
  end

  defcontext InvalidContext do
    layer(ContexirContextActivationTest.RequiresMobileLayer, when: & &1.enabled)
  end

  test "context helpers read and update process-local context" do
    Contexir.Context.with_context(%{user: "Alice"}, fn ->
      assert Contexir.Context.current() == %{user: "Alice"}
      assert Contexir.Context.get(:user) == "Alice"
      assert Contexir.Context.get(:missing, :fallback) == :fallback

      Contexir.Context.put(:role, :admin)
      Contexir.Context.update(:count, 1, &(&1 + 1))

      assert Contexir.Context.current() == %{user: "Alice", role: :admin, count: 1}
    end)

    assert Contexir.Context.current() == %{}
  end

  test "legacy context helpers read set and update context" do
    Contexir.Context.set_ctx(%{count: 1})

    try do
      assert Contexir.Context.get_ctx() == %{count: 1}

      Contexir.Context.update_ctx(&Map.update!(&1, :count, fn count -> count + 1 end))

      assert Contexir.Context.get_ctx() == %{count: 2}
    after
      Contexir.Context.set_ctx(%{})
    end
  end

  test "resolves context rules into active layers" do
    assert Contexir.Layer.resolve_context!(
             ContexirContextActivationTest.ApplicationContext,
             %{network: :cellular, battery: 10}
           ) == [
             ContexirContextActivationTest.MobileLayer,
             ContexirContextActivationTest.LowBatteryLayer
           ]

    assert Contexir.Layer.resolve_context!(
             ContexirContextActivationTest.ApplicationContext,
             %{network: :wifi, battery: 90}
           ) == []
  end

  test "resolve_context returns composition errors" do
    assert Contexir.Layer.resolve_context(
             ContexirContextActivationTest.InvalidContext,
             %{enabled: true}
           ) ==
             {:error,
              {:missing_requirements,
               [
                 %{
                   layer: ContexirContextActivationTest.RequiresMobileLayer,
                   requires: ContexirContextActivationTest.MobileLayer
                 }
               ]}}
  end

  test "with_context activates layers selected by context rules" do
    result =
      Contexir.with_context(
        ContexirContextActivationTest.ApplicationContext,
        %{network: :cellular, battery: 10},
        ContexirContextActivationTest.Target.execute(%{string: "start"}, %{})
      )

    assert result.string == "start mobile battery target"
  end

  test "with_context passes the selected context to the target call" do
    assert Contexir.with_context(
             ContexirContextActivationTest.ApplicationContext,
             %{network: :wifi, battery: 90},
             ContexirContextActivationTest.Target.read(%{}, %{})
           ) == %{network: :wifi, battery: 90}
  end

  test "context and active layers remain process-local" do
    parent = self()

    try do
      Contexir.Context.with_context(%{request_id: :parent}, fn ->
        Contexir.Context.activate(ContexirContextActivationTest.MobileLayer)

        spawn(fn ->
          send(parent, {Contexir.Context.current(), Contexir.Context.active_layers()})
        end)

        assert_receive {%{}, []}
        assert Contexir.Context.current() == %{request_id: :parent}
        assert Contexir.Context.active_layers() == [ContexirContextActivationTest.MobileLayer]
      end)
    after
      Contexir.Context.deactivate(ContexirContextActivationTest.MobileLayer)
    end
  end

  test "plain Task does not inherit context or active layers" do
    Contexir.Context.with_scope(
      [ContexirContextActivationTest.MobileLayer],
      %{request_id: :parent},
      fn ->
        task =
          Task.async(fn ->
            {Contexir.Context.current(), Contexir.Context.active_layers()}
          end)

        assert Task.await(task) == {%{}, []}
      end
    )
  end

  test "with_scope restores context and layers after exceptions" do
    Contexir.Context.with_scope([ContexirContextActivationTest.MobileLayer], %{outer: true}, fn ->
      assert_raise RuntimeError, "boom", fn ->
        Contexir.Context.with_scope(
          [ContexirContextActivationTest.LowBatteryLayer],
          %{inner: true},
          fn -> raise "boom" end
        )
      end

      assert Contexir.Context.current() == %{outer: true}
      assert Contexir.Context.active_layers() == [ContexirContextActivationTest.MobileLayer]
    end)

    assert Contexir.Context.current() == %{}
    assert Contexir.Context.active_layers() == []
  end

  test "Contexir.Task inherits context and active layers" do
    Contexir.Context.with_scope(
      [ContexirContextActivationTest.MobileLayer],
      %{request_id: :parent},
      fn ->
        task =
          Contexir.Task.async(fn ->
            {
              Contexir.Context.current(),
              Contexir.Context.active_layers(),
              Contexir.with_layers(
                [],
                ContexirContextActivationTest.Target.execute(%{string: "start"}, %{})
              )
            }
          end)

        assert Contexir.Task.await(task) ==
                 {
                   %{request_id: :parent},
                   [ContexirContextActivationTest.MobileLayer],
                   %{string: "start mobile target"}
                 }
      end
    )
  end

  test "Contexir.Task failure does not leak scope into caller" do
    old_trap_exit = Process.flag(:trap_exit, true)

    try do
      ExUnit.CaptureLog.capture_log(fn ->
        Contexir.Context.with_scope(
          [ContexirContextActivationTest.MobileLayer],
          %{request_id: :parent},
          fn ->
            task =
              Contexir.Task.async(fn ->
                Contexir.Context.put(:child_only, true)
                Contexir.Context.activate(ContexirContextActivationTest.LowBatteryLayer)
                raise "task failed"
              end)

            assert catch_exit(Contexir.Task.await(task))

            assert Contexir.Context.current() == %{request_id: :parent}
            assert Contexir.Context.active_layers() == [ContexirContextActivationTest.MobileLayer]
          end
        )
      end)
    after
      Process.flag(:trap_exit, old_trap_exit)
    end
  end

  test "Contexir.Task async module function arity inherits scope" do
    Contexir.Context.with_scope([], %{request_id: :module_task}, fn ->
      task =
        Contexir.Task.async(
          ContexirContextActivationTest.Target,
          :read,
          [%{}, %{}]
        )

      assert Contexir.Task.await(task) == %{request_id: :module_task}
    end)
  end
end
