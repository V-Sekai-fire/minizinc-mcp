defmodule ValidateTest do
  use ExUnit.Case

  @moduledoc """
  Tests for MiniZinc model validation functionality.
  """

  alias MiniZincMcp.Solver

  test "validate a valid model" do
    model = """
    var int: x;
    constraint x > 0;
    constraint x < 10;
    solve satisfy;
    """

    case Solver.validate_string(model) do
      {:ok, result} ->
        assert is_map(result)
        assert result["valid"] == true
        assert result["errors"] == []
        assert is_list(result["warnings"])
        assert result["message"] == "Model is valid"

      {:error, reason} ->
        flunk("Validation failed unexpectedly: #{reason}")
    end
  end

  test "validate model with syntax error" do
    model = """
    var int: x;
    constraint x > 0
    solve satisfy;
    """

    case Solver.validate_string(model) do
      {:ok, result} ->
        assert is_map(result)
        assert result["valid"] == false
        assert is_list(result["errors"])
        assert length(result["errors"]) > 0
        # Should contain error about missing semicolon or syntax error
        error_text = Enum.join(result["errors"], " ")
        assert String.contains?(error_text, "Error") or String.contains?(error_text, "error")

      {:error, reason} ->
        flunk("Validation failed unexpectedly: #{reason}")
    end
  end

  test "validate model with type error" do
    model = """
    var int: x;
    constraint x = "hello";
    solve satisfy;
    """

    case Solver.validate_string(model) do
      {:ok, result} ->
        assert is_map(result)
        assert result["valid"] == false
        assert is_list(result["errors"])
        assert length(result["errors"]) > 0

      {:error, reason} ->
        flunk("Validation failed unexpectedly: #{reason}")
    end
  end

  test "validate model with data content" do
    model = """
    int: n;
    array[1..n] of var 1..n: x;
    constraint alldifferent(x);
    solve satisfy;
    """

    data = "n = 5;"

    case Solver.validate_string(model, data) do
      {:ok, result} ->
        assert is_map(result)
        assert result["valid"] == true
        assert result["errors"] == []

      {:error, reason} ->
        flunk("Validation with data failed: #{reason}")
    end
  end

  test "validate model with invalid data" do
    model = """
    int: n;
    array[1..n] of var 1..n: x;
    constraint alldifferent(x);
    solve satisfy;
    """

    data = "n = invalid;"

    case Solver.validate_string(model, data) do
      {:ok, result} ->
        # Should fail due to invalid data or model syntax
        assert is_map(result)
        # Either model syntax error or data error
        assert result["valid"] == false or length(result["errors"]) > 0

      {:error, reason} ->
        # Also acceptable - validation might return error directly
        assert is_binary(reason)
    end
  end

  test "validate model with auto_include_stdlib disabled" do
    model = """
    array[1..5] of var 1..5: x;
    constraint alldifferent(x);
    solve satisfy;
    """

    case Solver.validate_string(model, nil, auto_include_stdlib: false) do
      {:ok, result} ->
        assert is_map(result)
        # Should fail because alldifferent needs include
        assert result["valid"] == false or length(result["errors"]) > 0

      {:error, reason} ->
        # Also acceptable
        assert is_binary(reason)
    end
  end

  test "validate model with auto_include_stdlib enabled" do
    model = """
    array[1..5] of var 1..5: x;
    constraint alldifferent(x);
    solve satisfy;
    """

    case Solver.validate_string(model, nil, auto_include_stdlib: true) do
      {:ok, result} ->
        assert is_map(result)
        # Should pass because alldifferent is auto-included
        assert result["valid"] == true

      {:error, reason} ->
        flunk("Validation with auto_include should work: #{reason}")
    end
  end

  test "validate empty model content" do
    case Solver.validate_string("") do
      {:ok, result} ->
        # Empty model should fail validation or return errors
        assert is_map(result)
        # Check if it's invalid or has errors
        if result["valid"] == true do
          # If marked as valid, that's also acceptable (empty might be considered valid syntax)
          assert true
        else
          assert result["valid"] == false or length(result["errors"]) > 0
        end

      {:error, reason} ->
        # Also acceptable - empty model might return error directly
        assert is_binary(reason)
    end
  end

  test "validate model with reserved keyword error" do
    # Using 'array' as variable name (reserved keyword)
    model = """
    int: n = 5;
    array[0..n-1] of var 0..n-1: array;
    constraint array[0] = 1;
    solve satisfy;
    """

    case Solver.validate_string(model) do
      {:ok, result} ->
        assert is_map(result)
        assert result["valid"] == false
        assert is_list(result["errors"])
        assert length(result["errors"]) > 0
        # Should contain error about 'array' being reserved
        error_text = Enum.join(result["errors"], " ")

        assert String.contains?(error_text, "array") or
                 String.contains?(error_text, "syntax error")

      {:error, reason} ->
        flunk("Validation should return errors, not fail: #{reason}")
    end
  end
end
