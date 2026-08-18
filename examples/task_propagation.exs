import Contexir.Layer
require Contexir

defmodule Examples.TaskPropagation.Worker do
  use Contexir

  def run(value, _ctx) do
    {value, Contexir.Context.current()}
  end
end

deflayer Examples.TaskPropagation.Trace do
  defpartial Examples.TaskPropagation.Worker.run(value, _ctx), mode: :around do
    continue(
      Examples.TaskPropagation.Worker,
      :run,
      ["traced #{value}"]
    )
  end
end

Contexir.Context.with_scope(
  [Examples.TaskPropagation.Trace],
  %{request_id: "req-123"},
  fn ->
    task =
      Contexir.Task.async(fn ->
        Contexir.with_layers(
          [],
          Examples.TaskPropagation.Worker.run("job", Contexir.Context.current())
        )
      end)

    IO.inspect(Contexir.Task.await(task), label: "task result")
  end
)
