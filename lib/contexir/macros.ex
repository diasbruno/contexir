defmodule Contexir.Macros do
  @moduledoc """
  DSL:
  - `deflayer Name, opts`
  - `defpartial Base.fun(args...), mode: :before/:around/:after`
  - `use_layers [A, B, C]`
  """

  @const_predicate_function_true {:fn, [],
                                  [
                                    {:->, [],
                                    [
                                      [{:_m, [], nil}, {:_f, [], nil}, {:_a, [], nil}, {:_c, [], nil}],
                                      true
                                    ]}
                                  ]}

  # Define a new layer module with optional predicate
  defmacro deflayer(name, opts \\ [], do: block) do
    predicate = Keyword.get(opts, :when, @const_predicate_function_true)

    {:fn, _x,
     [
       {:->, _y,
       [
         args,
         body
       ]}
     ]} = predicate

    m = quote do
      defmodule unquote(name) do
        import Contexir.Macros

        def __predicate__(unquote_splicing(args)) do
          unquote(body)
        end

        unquote(block)

        @doc """
        Default case.
        """
        def has_mode_defined(_mod, _fun, _mode), do: false
      end
    end

    IO.puts(Macro.to_string(m))
    m
  end

  # Define a partial method with optional mode
  defmacro defpartial(signature, opts \\ [], do: body) do
    {{:., _x, [{_y, _m, mod}, fun]}, _z, args} = signature

    the_module = Module.concat(mod)

    mode = Keyword.get(opts, :mode, :around)

    m = quote do
      def unquote(fun)(unquote(the_module), unquote(mode), unquote_splicing(args)) do
        import Contexir.Dispatch, only: [continue: 3]
        unquote(body)
      end

      def has_mode_defined(unquote(the_module), unquote(fun), unquote(mode)), do: true
    end

    IO.puts(Macro.to_string(m))
    m
  end

  # Define a grouped (composite) layer
  defmacro use_layers(layers) do
    quote do
      Module.put_attribute(__MODULE__, :included_layers, unquote(layers))
      def __included_layers__, do: @included_layers
    end
  end
end
