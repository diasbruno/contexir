defmodule ContexirTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  defmodule Account do
    use Contexir

    def withdraw(acc, amt, _ctx) do
      %{acc | balance: acc.balance - amt}
    end
  end

  deflayer GiveHundred do
    refine ContexirTest.Account do
      defpartial withdraw(acc, amt, _ctx) do
        %{balance: b} = acc
        continue([%{balance: b + 100}, amt])
      end
    end
  end

  deflayer TakeTenPercent do
    refine ContexirTest.Account do
      defpartial withdraw(acc, amt, _ctx) do
        %{balance: b} = acc
        continue([%{balance: b * 0.9}, amt])
      end
    end
  end

  test "plain function call" do
    %{balance: b} = ContexirTest.Account.withdraw(%{balance: 100}, 40, %{user: "Alice"})
    assert b == 60
  end

  test "run simple layer" do
    layers = [ContexirTest.GiveHundred]

    %{balance: b} =
      Contexir.with_layers(
        layers,
        ContexirTest.Account.withdraw(%{balance: 100}, 40, %{user: "Alice"})
      )

    assert b == 160
  end

  test "run 2 layers" do
    layers = [ContexirTest.GiveHundred, ContexirTest.TakeTenPercent]

    %{balance: b} =
      Contexir.with_layers(
        layers,
        ContexirTest.Account.withdraw(%{balance: 100}, 40, %{user: "Alice"})
      )

    assert b == 140
  end
end
