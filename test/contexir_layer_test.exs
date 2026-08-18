defmodule ContexirLayerTest do
  use ExUnit.Case, async: false
  import Contexir.Layer
  require Contexir

  defmodule Target do
    def execute(acc, _ctx), do: acc
  end

  deflayer ExampleLayer do
    defpartial ContexirLayerTest.Target.execute(acc, _ctx), mode: :around do
      acc
    end

    defpartial ContexirLayerTest.Target.execute(_acc, _ctx), mode: :before do
      :ok
    end

    defpartial ContexirLayerTest.Target.execute(_acc, _ctx), mode: :after do
      :ok
    end
  end

  deflayer PredicateLayer, when: fn _mod, _fun, _args, ctx -> ctx[:enabled] end do
    defpartial ContexirLayerTest.Target.execute(acc, _ctx), mode: :before do
      acc
    end
  end

  deflayer GroupLayer do
    use_layers([ContexirLayerTest.ExampleLayer])
  end

  deflayer RelationshipLayer do
    requires(ContexirLayerTest.ExampleLayer)
    conflicts_with(ContexirLayerTest.PredicateLayer)
    before(ContexirLayerTest.PredicateLayer)
    after_layer(ContexirLayerTest.GroupLayer)
  end

  deflayer RefineLayer do
    refine ContexirLayerTest.Target do
      defpartial execute(acc, _ctx), mode: :around do
        continue([acc ++ [:refined]])
      end
    end
  end

  test "layer metadata describes partials predicate and included layers" do
    assert Contexir.Layer.info(ContexirLayerTest.ExampleLayer) == %{
             module: ContexirLayerTest.ExampleLayer,
             partials: [
               %{module: ContexirLayerTest.Target, function: :execute, mode: :around},
               %{module: ContexirLayerTest.Target, function: :execute, mode: :before},
               %{module: ContexirLayerTest.Target, function: :execute, mode: :after}
             ],
             includes: [],
             requires: [],
             conflicts_with: [],
             before: [],
             after: [],
             predicate?: false
           }

    assert Contexir.Layer.info(ContexirLayerTest.PredicateLayer).predicate? == true

    assert Contexir.Layer.info(ContexirLayerTest.GroupLayer).includes == [
             ContexirLayerTest.ExampleLayer
           ]
  end

  test "layer metadata describes composition relationships" do
    info = Contexir.Layer.info(ContexirLayerTest.RelationshipLayer)

    assert info.requires == [ContexirLayerTest.ExampleLayer]
    assert info.conflicts_with == [ContexirLayerTest.PredicateLayer]
    assert info.before == [ContexirLayerTest.PredicateLayer]
    assert info.after == [ContexirLayerTest.GroupLayer]
  end

  test "refine scopes local partials to a target module" do
    assert Contexir.Layer.info(ContexirLayerTest.RefineLayer).partials == [
             %{module: ContexirLayerTest.Target, function: :execute, mode: :around}
           ]
  end

  test "continue shorthand uses the current refined function" do
    assert Contexir.with_layers(
             [ContexirLayerTest.RefineLayer],
             ContexirLayerTest.Target.execute([], %{})
           ) == [:refined]
  end
end
