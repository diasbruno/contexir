defmodule ContexirUseLayersTest do
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
    defpartial ContexirUseLayersTest.Target.execute(acc, ctx), mode: :around do
      %{string: s} = acc
      result = continue(
        ContexirUseLayersTest.Target,
        :execute,
        [%{string: s <> " around before-after_part"}])

      result
    end

    defpartial ContexirUseLayersTest.Target.execute(acc, ctx), mode: :before do
      Process.put(:target, 1)
    end

    defpartial ContexirUseLayersTest.Target.execute(acc, ctx), mode: :after do
      x = Process.get(:target) || 0
      Process.put(:target, x - 1)
    end
  end

  deflayer UseLayer do
    use_layers [ContexirUseLayersTest.BeforeAfter]
  end

  #
  # Tests
  #

  # @tag :skip
  test "run before/after layer" do
    layers = [ContexirUseLayersTest.UseLayer]

    %{string: b} =
      Contexir.with_layers layers,
      ContexirUseLayersTest.Target.execute(%{string: "start_string"}, %{user: "Alice"})
    x = Process.get(:target)
    assert x == 0
    assert b == "start_string around before-after_part target_part"
  end
end
