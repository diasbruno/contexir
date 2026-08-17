# test/contexir_test.exs
defmodule ContexirTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  #
  # Setup base module and layers
  #
  defmodule Account do
    use Contexir

    def withdraw(acc, amt, ctx) do
      %{acc | balance: acc.balance - amt}
    end
  end

  deflayer GiveHundred do
    defpartial ContexirTest.Account.withdraw(acc, amt, ctx) do
      %{balance: b} = acc
      continue(ContexirTest.Account, :withdraw, [%{balance: b + 100}, amt])
    end
  end

  deflayer TakeTenPercent do
    defpartial ContexirTest.Account.withdraw(acc, amt, ctx) do
      %{balance: b} = acc
      continue(ContexirTest.Account, :withdraw, [%{balance: b * 0.9}, amt])
    end
  end

  #
  # Tests
  #

  # @tag :skip
  test "plain function call" do
    %{balance: b} = ContexirTest.Account.withdraw(%{balance: 100}, 40, %{user: "Alice"})
    assert b == 60
  end

  # @tag :skip
  test "run simple layer" do
    layers = [ContexirTest.GiveHundred]

    %{balance: b} =
      Contexir.with_layers(
        layers,
        ContexirTest.Account.withdraw(%{balance: 100}, 40, %{user: "Alice"})
      )

    assert b == 160
  end

  # @tag :skip
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
