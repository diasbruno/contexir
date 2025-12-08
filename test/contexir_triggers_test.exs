defmodule ContexirTriggersTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO
  import Contexir.Macros
  require Contexir

  defmodule Target do
    use Contexir.Base

    def execute(acc, ctx) do
      IO.inspect("Primary")
      %{acc | string: acc.string <> " target_part"}
    end
  end

  deflayer BeforeAfter do
    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :around do
      IO.inspect("a around")
      %{string: s} = acc
      result = continue(
        ContexirTriggersTest.Target,
        :execute,
        [%{string: s <> " around before-after_part"}])
      IO.inspect("a around end")
      result
    end

    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :before do
      IO.inspect("a before")
      Process.put(:target, 1)
    end

    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :after do
      IO.inspect("a after")
      x = Process.get(:target) || 0
      Process.put(:target, x - 1)
    end
  end

  #
  # Tests
  #

  # @tag :skip
  test "run before/after layer" do
    layers = [ContexirTriggersTest.BeforeAfter]

    %{string: b} =
      Contexir.with_layers layers,
      ContexirTriggersTest.Target.execute(%{string: "start_string"}, %{user: "Alice"})
    x = Process.get(:target)
    assert x == 0
    assert b == "start_string around before-after_part target_part"
  end
end
