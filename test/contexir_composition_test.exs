defmodule ContexirCompositionTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  defmodule Target do
    use Contexir

    def execute(acc, _ctx), do: acc
  end

  deflayer Outer do
    defpartial ContexirCompositionTest.Target.execute(acc, _ctx), mode: :around do
      continue(ContexirCompositionTest.Target, :execute, [acc])
    end
  end

  deflayer Inner do
    defpartial ContexirCompositionTest.Target.execute(acc, _ctx), mode: :around do
      continue(ContexirCompositionTest.Target, :execute, [acc])
    end
  end

  deflayer GroupLayer do
    use_layers([ContexirCompositionTest.Outer, ContexirCompositionTest.Inner])
  end

  deflayer RequiresOuter do
    requires(ContexirCompositionTest.Outer)
  end

  deflayer ConflictsWithInner do
    conflicts_with(ContexirCompositionTest.Inner)
  end

  test "resolves grouped layers and removes duplicates" do
    assert Contexir.Layer.resolve([
             ContexirCompositionTest.GroupLayer,
             ContexirCompositionTest.Outer
           ]) ==
             {:ok, [ContexirCompositionTest.Outer, ContexirCompositionTest.Inner]}
  end

  test "validates required layers during resolution" do
    assert Contexir.Layer.resolve([ContexirCompositionTest.RequiresOuter]) ==
             {:error,
              {:missing_requirements,
               [
                 %{
                   layer: ContexirCompositionTest.RequiresOuter,
                   requires: ContexirCompositionTest.Outer
                 }
               ]}}

    assert Contexir.Layer.resolve([
             ContexirCompositionTest.Outer,
             ContexirCompositionTest.RequiresOuter
           ]) ==
             {:ok, [ContexirCompositionTest.Outer, ContexirCompositionTest.RequiresOuter]}
  end

  test "validates conflicting layers during resolution" do
    assert Contexir.Layer.resolve([
             ContexirCompositionTest.ConflictsWithInner,
             ContexirCompositionTest.Inner
           ]) ==
             {:error,
              {:conflicting_layers,
               [
                 %{
                   layer: ContexirCompositionTest.ConflictsWithInner,
                   conflicts_with: ContexirCompositionTest.Inner
                 }
               ]}}
  end

  test "resolve! raises when relationships are invalid" do
    assert_raise ArgumentError, ~r/invalid layer composition/, fn ->
      Contexir.Layer.resolve!([ContexirCompositionTest.RequiresOuter])
    end
  end

  test "with_layers validates composition before activation" do
    assert_raise ArgumentError, ~r/invalid layer composition/, fn ->
      Contexir.with_layers(
        [ContexirCompositionTest.RequiresOuter],
        ContexirCompositionTest.Target.execute(%{}, %{})
      )
    end
  end
end
