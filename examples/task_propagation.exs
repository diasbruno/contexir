import Contexir.Layer
require Contexir

# Process dictionary state is process-local, so a plain Task would not inherit
# the caller's active layers or context. Contexir.Task captures the current scope
# and installs it inside the spawned task before running the function.

defmodule Examples.TaskPropagation.Worker do
  use Contexir

  def run(value, _ctx) do
    {value, Contexir.Context.current()}
  end
end

deflayer Examples.TaskPropagation.Trace do
  refine Examples.TaskPropagation.Worker do
    defpartial run(value, _ctx), mode: :around do
      continue(["traced #{value}"])
    end
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
