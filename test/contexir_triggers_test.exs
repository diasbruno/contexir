defmodule ContexirTriggersTest do
  use ExUnit.Case, async: false
  import Contexir.Macros
  require Contexir

  defmodule Target do
    use Contexir.Base

    def execute(acc, ctx) do
      %{acc | string: acc.string <> " target_part"}
    end
  end

  deflayer BeforeAfter do
    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :around do
      %{string: s} = acc
      continue(
        ContexirTriggersTest.Target,
        :execute,
        [%{string: s <> " around before-after_part"}])
    end

    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :before do
      Process.put(:target, 1)
    end

    defpartial ContexirTriggersTest.Target.execute(acc, ctx), mode: :after do
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
