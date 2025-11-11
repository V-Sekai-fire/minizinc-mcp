# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Solver do
  @moduledoc """
  MiniZinc solver using System.cmd to call minizinc command-line tool with JSON output.

  This solver uses the standard MiniZinc command-line interface and parses JSON output.
  No NIFs are required - everything is done via external process communication.
  """

  require Logger

  @doc """
  Solves a MiniZinc model file using the minizinc command-line tool.

  ## Parameters

  - `model_path`: Path to .mzn MiniZinc model file
  - `data_path`: Optional path to .dzn data file
  - `opts`: Options keyword list
    - `:solver` - Solver name (default: "chuffed")
    - `:timeout` - Timeout in milliseconds (default: 60000)
    - `:solver_options` - Additional solver options

  ## Returns

  - `{:ok, solution}` - Parsed solution as map
  - `{:error, reason}` - Error reason
  """
  @spec solve(String.t(), String.t() | nil, keyword()) :: {:ok, map()} | {:error, String.t()}
  def solve(model_path, data_path \\ nil, opts \\ []) do
    # Only support chuffed solver
    solver = "chuffed"
    timeout = Keyword.get(opts, :timeout, 60_000)
    solver_options = Keyword.get(opts, :solver_options, [])

    if not File.exists?(model_path) do
      {:error, "MiniZinc model file not found: #{model_path}"}
    else
      build_and_run_command(model_path, data_path, solver, timeout, solver_options)
    end
  end

  @doc """
  Solves MiniZinc model from string content.

  Writes the content to a temporary file and solves it.
  """
  @spec solve_string(String.t(), String.t() | nil, keyword()) :: {:ok, map()} | {:error, String.t()}
  def solve_string(model_content, data_content \\ nil, opts \\ []) do
    # Parse DZN data content if provided
    parsed_data = if data_content, do: parse_dzn_output(data_content), else: %{}

    case Briefly.create(prefix: "minizinc_") do
      {:ok, model_file_base} ->
        # Briefly doesn't add extensions, so we need to add it manually
        model_file = model_file_base <> ".mzn"
        try do
          :ok = File.write!(model_file, model_content)
          # Verify file exists and is readable
          unless File.exists?(model_file) do
            raise "Temporary file was not created: #{model_file}"
          end
          data_file = maybe_create_data_file(data_content)
          case solve(model_file, data_file, opts) do
            {:ok, solution} ->
              # Merge parsed input data into solution for reference
              solution_with_data = Map.merge(solution, %{input_data: parsed_data})
              {:ok, solution_with_data}

            error ->
              error
          end
        rescue
          e -> {:error, "Failed to write temporary file: #{inspect(e)}"}
        end

      {:error, reason} ->
        {:error, "Failed to create temporary file: #{inspect(reason)}"}
    end
  end

  defp maybe_create_data_file(nil), do: nil
  defp maybe_create_data_file(data_content) do
    case Briefly.create(prefix: "minizinc_") do
      {:ok, data_file_base} ->
        # Briefly doesn't add extensions, so we need to add it manually
        data_file = data_file_base <> ".dzn"
        File.write!(data_file, data_content)
        # Verify file exists
        unless File.exists?(data_file) do
          raise "Data file was not created: #{data_file}"
        end
        data_file

      {:error, reason} ->
        raise "Failed to create data file: #{inspect(reason)}"
    end
  end

  @doc """
  Checks if MiniZinc is available.
  """
  @spec available?() :: boolean()
  def available? do
    case System.cmd("minizinc", ["--version"], stderr_to_stdout: true, timeout: 5000) do
      {_output, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Lists available solvers.
  """
  @spec list_solvers() :: {:ok, [String.t()]} | {:error, String.t()}
  def list_solvers do
    task = Task.async(fn ->
      System.cmd("minizinc", ["--solvers"], stderr_to_stdout: true)
    end)

    case Task.yield(task, 5000) || Task.shutdown(task) do
      {:ok, {output, 0}} ->
        solvers = parse_solver_list(output)
        {:ok, solvers}

      {:ok, {output, _}} ->
        {:error, "Failed to list solvers: #{String.slice(output, 0, 200)}"}

      nil ->
        {:error, "Timeout listing solvers"}

      {:exit, reason} ->
        {:error, "Process exited: #{inspect(reason)}"}
    end
  rescue
    e -> {:error, "Error listing solvers: #{inspect(e)}"}
  end

  # Private functions

  defp build_and_run_command(model_path, data_path, solver, timeout, solver_options) do
    cmd_args = build_command_args(model_path, data_path, solver, solver_options)

    Logger.debug("Running minizinc with args: #{inspect(cmd_args)}")

    try do
      task = Task.async(fn ->
        System.cmd("minizinc", cmd_args, stderr_to_stdout: true)
      end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {output, 0}} ->
          parse_json_output(output)

        {:ok, {output, status}} ->
          # Try to parse even if status is non-zero (MiniZinc may return solutions with warnings)
          case parse_json_output(output) do
            {:ok, solution} -> {:ok, solution}
            _ -> {:error, "MiniZinc failed with status #{status}: #{String.slice(output, 0, 500)}"}
          end

        nil ->
          {:error, "MiniZinc execution timed out after #{timeout}ms"}

        {:exit, reason} ->
          {:error, "MiniZinc process exited: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "MiniZinc execution error: #{inspect(e)}"}
    end
  end

  defp build_command_args(model_path, data_path, solver, solver_options) do
    args = [
      "--solver", solver,
      "--json-stream"
    ]

    # Add solver-specific options
    args = add_solver_options(args, solver_options)

    # Add model file
    args = args ++ [model_path]

    # Add data file if provided
    if data_path && File.exists?(data_path) do
      args ++ [data_path]
    else
      args
    end
  end

  defp add_solver_options(args, opts) when is_list(opts) do
    Enum.reduce(opts, args, fn opt, acc ->
      case opt do
        {:time_limit, ms} ->
          seconds = div(ms, 1000)
          acc ++ ["--time-limit", Integer.to_string(seconds)]

        {:free_search, true} ->
          acc ++ ["--free-search"]

        {:num_solutions, n} ->
          acc ++ ["--num-solutions", Integer.to_string(n)]

        _ ->
          acc
      end
    end)
  end

  defp add_solver_options(args, _), do: args

  defp parse_json_output(output) do
    # Handle non-binary output
    output_str = if is_binary(output), do: output, else: inspect(output)

    # MiniZinc JSON output is newline-delimited JSON
    # Each line is a JSON object with type: "solution", "status", "error", etc.
    lines = String.split(output_str, "\n") |> Enum.filter(&(&1 != ""))

    solution = %{}
    status = nil
    error = nil

    {solution, status, error} =
      Enum.reduce(lines, {solution, status, error}, fn line, {sol_acc, stat_acc, err_acc} ->
        case Jason.decode(line) do
          {:ok, json} ->
            case json do
              # Prioritize JSON field over text output
              %{"type" => "solution", "json" => json_solution} when is_map(json_solution) ->
                # Direct JSON solution - preferred format
                # Convert string keys to atoms for consistency, but keep both
                atom_keys = json_solution |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end) |> Map.new()
                string_keys = json_solution
                merged = Map.merge(sol_acc, atom_keys) |> Map.merge(string_keys)
                {merged, stat_acc, err_acc}

              %{"type" => "solution", "json" => json_solution} when is_list(json_solution) ->
                # JSON solution as list (array of solutions)
                {Map.merge(sol_acc, %{solutions: json_solution}), stat_acc, err_acc}

              %{"type" => "solution", "output" => output_text} ->
                # Only support DZN format output
                dzn_text = extract_dzn_output(output_text)
                if dzn_text != "" do
                  parsed = parse_dzn_output(dzn_text)
                  # Build solution map with parsed variables and DZN output
                  merged =
                    sol_acc
                    |> Map.merge(parsed)
                    |> Map.put(:output, output_text)
                    |> Map.put(:dzn_output, dzn_text)
                  {merged, stat_acc, err_acc}
                else
                  # No DZN output available - return error or empty solution
                  Logger.warning("Solution has no DZN output format, only: #{inspect(Map.keys(output_text))}")
                  {sol_acc, stat_acc, err_acc}
                end

              %{"type" => "status", "status" => stat} ->
                {sol_acc, stat, err_acc}

              %{"type" => "error", "message" => msg} ->
                {sol_acc, stat_acc, msg}

              %{"type" => "solution"} ->
                # Solution without json or output field - might have variables directly
                solution_vars = Map.drop(json, ["type"])
                {Map.merge(sol_acc, solution_vars), stat_acc, err_acc}

              _ ->
                {sol_acc, stat_acc, err_acc}
            end

          {:error, decode_error} ->
            # If JSON decode fails, log and skip (don't fall back to text parsing)
            Logger.warning("Failed to parse JSON line: #{inspect(line)} - #{inspect(decode_error)}")
            {sol_acc, stat_acc, err_acc}
        end
      end)

    # Return appropriate result
    cond do
      error -> {:error, error}
      status in ["UNSATISFIABLE", "UNSAT"] -> {:error, "Problem is unsatisfiable"}
      map_size(solution) > 0 -> {:ok, solution}
      status == "OPTIMAL_SOLUTION" or status == "SATISFIED" -> {:ok, %{status: status}}
      true -> {:ok, %{}}
    end
  end

  defp extract_dzn_output(%{"dzn" => text}) when is_binary(text), do: text
  defp extract_dzn_output(_), do: ""

  defp parse_dzn_output(output) when is_binary(output) and output != "" do
    # Parse complete DZN format
    # Supports:
    # - Simple assignments: variable = value;
    # - Arrays: array = [1, 2, 3];
    # - Multi-dimensional arrays: array2d = [| 1, 2 | 3, 4 |];
    # - Sets: set = {1, 2, 3};
    # - Comments: % comment
    # - Multi-line values
    
    # Remove comments and split into statements
    statements = extract_dzn_statements(output)
    
    Enum.reduce(statements, %{}, fn statement, acc ->
      case parse_dzn_statement(statement) do
        {var_name, value} -> Map.put(acc, var_name, value)
        nil -> acc
      end
    end)
  end

  defp parse_dzn_output(""), do: %{}
  defp parse_dzn_output(nil), do: %{}
  defp parse_dzn_output(_), do: %{}

  defp extract_dzn_statements(output) do
    # Split by semicolons and filter out comments/empty lines
    output
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    |> Enum.map(&remove_comment/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp remove_comment(line) do
    # Remove DZN comments (% ...)
    case String.split(line, "%", parts: 2) do
      [code, _comment] -> String.trim(code)
      [code] -> String.trim(code)
    end
  end

  defp parse_dzn_statement(statement) do
    # Match: variable = value
    case Regex.run(~r/^(\w+)\s*=\s*(.+)$/, statement) do
      [_, var_name, value_str] ->
        value = parse_dzn_value(String.trim(value_str))
        {String.to_atom(var_name), value}

      _ ->
        nil
    end
  end

  defp parse_dzn_value(value_str) do
    value_str = String.trim(value_str)
    
    cond do
      # Multi-dimensional array: [| ... |]
      String.starts_with?(value_str, "[|") and String.ends_with?(value_str, "|]") ->
        parse_multidim_array(value_str)

      # Regular array: [...]
      String.starts_with?(value_str, "[") and String.ends_with?(value_str, "]") ->
        parse_array(value_str)

      # Set: {...}
      String.starts_with?(value_str, "{") and String.ends_with?(value_str, "}") ->
        parse_set(value_str)

      # Boolean
      value_str == "true" -> true
      value_str == "false" -> false

      # Integer
      Regex.match?(~r/^-?\d+$/, value_str) -> String.to_integer(value_str)

      # Float
      Regex.match?(~r/^-?\d+\.\d+$/, value_str) -> String.to_float(value_str)

      # String (quoted)
      String.starts_with?(value_str, "\"") and String.ends_with?(value_str, "\"") ->
        String.slice(value_str, 1..-2)

      # Default: return as string
      true -> value_str
    end
  end

  defp parse_multidim_array(array_str) do
    # Parse [| 1, 2 | 3, 4 |] format
    # Remove [| and |]
    content = array_str
    |> String.slice(2..-3)
    |> String.trim()

    # Split by | to get rows
    rows = String.split(content, "|")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))

    Enum.map(rows, fn row ->
      parse_array("[" <> row <> "]")
    end)
  end

  defp parse_set(set_str) do
    # Parse {1, 2, 3} format
    content = set_str
    |> String.slice(1..-2)
    |> String.trim()

    if content == "" do
      []
    else
      content
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&parse_dzn_value/1)
      |> Enum.uniq()
      |> Enum.sort()
    end
  end

  defp parse_value(value) do
    value = String.trim(value)

    cond do
      value == "true" -> true
      value == "false" -> false
      Regex.match?(~r/^-?\d+$/, value) -> String.to_integer(value)
      Regex.match?(~r/^-?\d+\.\d+$/, value) -> String.to_float(value)
      Regex.match?(~r/^\[.*\]$/, value) -> parse_array(value)
      true -> value
    end
  end

  defp parse_array(array_str) do
    # Parse [1, 2, 3] format
    content = array_str
    |> String.slice(1..-2)
    |> String.trim()

    if content == "" do
      []
    else
      content
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&parse_dzn_value/1)
    end
  end

  # Legacy parse_value for backward compatibility (now calls parse_dzn_value)
  defp parse_value(value) do
    parse_dzn_value(value)
  end

  defp parse_solver_list(output) do
    # Parse solver list from minizinc --solvers output
    output
    |> String.split("\n")
    |> Enum.filter(fn line ->
      String.contains?(line, ":") and not String.starts_with?(line, " ")
    end)
    |> Enum.map(fn line ->
      line
      |> String.split(":")
      |> List.first()
      |> String.trim()
    end)
    |> Enum.filter(&(&1 != ""))
  end

end
