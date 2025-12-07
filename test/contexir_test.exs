# test/contexir_test.exs
defmodule ContexirTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO
  import Contexir.Macros
  require Contexir

  #
  # Setup base module and layers
  #
  defmodule Account do
    use Contexir.Base

    def withdraw(acc, amt, ctx) do
      %{acc | balance: acc.balance - amt}
    end
  end

  deflayer GiveHundred do
    defpartial ContexirTest.Account.withdraw(acc, amt, ctx) do
      IO.inspect("giving hundred dollars")
      %{balance: b} = acc
      continue(Account, :withdraw, [%{balance: b + 100}, amt, ctx])
    end
  end

  #
  # Tests
  #

  test "plain function call" do
    %{balance: b} = ContexirTest.Account.withdraw(%{balance: 100}, 40, %{user: "Alice"})
    assert b == 60
  end

  test "run simple layer" do
    %{balance: b} = Contexir.with_layers [ContexirTest.GiveHundred],
      ContexirTest.Account.withdraw(%{balance: 100}, 40, %{user: "Alice"})
    assert b == 200
  end
end
