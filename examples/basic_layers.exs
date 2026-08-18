import Contexir.Layer
require Contexir

# This is the dispatch kernel in miniature:
#
#   * :before partials run for side effects and do not replace the result.
#   * :around partials decide when the next implementation runs through
#     continue/3.
#   * :after partials run once the result has been produced.
#
# The current context is already tracked by Contexir, so calls to continue/3 only
# pass the business arguments. The dispatcher appends the active context when it
# invokes the next function.

defmodule Examples.BasicLayers.Account do
  use Contexir

  def withdraw(account, amount, _ctx) do
    %{account | balance: account.balance - amount}
  end
end

deflayer Examples.BasicLayers.Logging do
  defpartial Examples.BasicLayers.Account.withdraw(_account, amount, _ctx), mode: :before do
    IO.puts("withdrawing #{amount}")
  end

  defpartial Examples.BasicLayers.Account.withdraw(account, amount, _ctx), mode: :around do
    result =
      continue(
        Examples.BasicLayers.Account,
        :withdraw,
        [account, amount]
      )

    IO.puts("new balance: #{result.balance}")
    result
  end

  defpartial Examples.BasicLayers.Account.withdraw(_account, _amount, _ctx), mode: :after do
    IO.puts("withdrawal complete")
  end
end

result =
  Contexir.with_layers(
    [Examples.BasicLayers.Logging],
    Examples.BasicLayers.Account.withdraw(%{balance: 100}, 25, %{})
  )

IO.inspect(result, label: "result")
