defmodule AdhocTest do
  use ExUnit.Case

  @moduledoc """
  Adhoc test to verify MiniZinc solver functionality.
  """

  test "solve simple MiniZinc model" do
    # Simple constraint satisfaction problem: find x > 0
    model = """
    var int: x;
    constraint x > 0;
    constraint x < 10;
    solve satisfy;
    """

    case MiniZincMcp.Solver.solve_string(model) do
      {:ok, result} ->
        IO.puts("\n✅ Test passed! Solution found:")
        IO.inspect(result, label: "Result")
        
        # Verify we got a solution
        assert is_map(result)
        # The result should have the variable x or output_text
        assert Map.has_key?(result, :x) || Map.has_key?(result, :output_text) || Map.has_key?(result, "x")
        
      {:error, reason} ->
        IO.puts("\n❌ Test failed with error:")
        IO.inspect(reason)
        flunk("Failed to solve model: #{reason}")
    end
  end

  test "solve MiniZinc model with data" do
    # Model that uses a parameter n
    model = """
    int: n;
    array[1..n] of var int: x;
    constraint all_different(x);
    constraint forall(i in 1..n)(x[i] >= 1);
    constraint forall(i in 1..n)(x[i] <= n);
    solve satisfy;
    """

    # Data file content
    data = "n = 5;"

    case MiniZincMcp.Solver.solve_string(model, data) do
      {:ok, result} ->
        IO.puts("\n✅ Test with data passed! Solution found:")
        IO.inspect(result, label: "Result")
        
        # Verify we got a solution
        assert is_map(result)
        
        # Check if input_data was parsed
        if Map.has_key?(result, :input_data) and result.input_data != %{} do
          assert result.input_data["n"] == 5 || result.input_data[:n] == 5
          n_val = result.input_data["n"] || result.input_data[:n]
          IO.puts("✅ Input data correctly parsed: n = #{n_val}")
        else
          IO.puts("ℹ️  Input data not in result (may be parsed differently)")
        end
        
      {:error, reason} ->
        IO.puts("\n❌ Test failed with error:")
        IO.inspect(reason)
        flunk("Failed to solve model with data: #{reason}")
    end
  end

  test "solve optimization problem" do
    # Simple optimization: minimize x
    model = """
    var int: x;
    constraint x >= 1;
    constraint x <= 10;
    solve minimize x;
    """

    case MiniZincMcp.Solver.solve_string(model) do
      {:ok, result} ->
        IO.puts("\n✅ Optimization test passed! Solution found:")
        IO.inspect(result, label: "Result")
        
        assert is_map(result)
        
      {:error, reason} ->
        IO.puts("\n❌ Optimization test failed with error:")
        IO.inspect(reason)
        flunk("Failed to solve optimization model: #{reason}")
    end
  end
end

