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
    solver = Keyword.get(opts, :solver, "chuffed")
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
    model_file = write_temp_file(model_content, ".mzn")
    data_file = if data_content, do: write_temp_file(data_content, ".dzn"), else: nil

    try do
      solve(model_file, data_file, opts)
    after
      File.rm(model_file)
      if data_file, do: File.rm(data_file)
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
    try do
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
                {Map.merge(sol_acc, json_solution), stat_acc, err_acc}

              %{"type" => "solution", "json" => json_solution} when is_list(json_solution) ->
                # JSON solution as list (array of solutions)
                {Map.merge(sol_acc, %{solutions: json_solution}), stat_acc, err_acc}

              %{"type" => "solution", "output" => output_text} ->
                # Fallback: parse text output only if JSON not available
                parsed = parse_minizinc_output(output_text)
                {Map.merge(sol_acc, parsed), stat_acc, err_acc}

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

  defp parse_minizinc_output(output) when is_binary(output) do
    # Parse MiniZinc format: variable_name = value;
    lines = String.split(output, "\n") |> Enum.filter(&(&1 != ""))

    Enum.reduce(lines, %{}, fn line, acc ->
      case Regex.run(~r/^(\w+)\s*=\s*([^;]+);/, line) do
        [_, var_name, value] ->
          parsed_value = parse_value(value)
          Map.put(acc, String.to_atom(var_name), parsed_value)

        _ ->
          acc
      end
    end)
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
    array_str
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_value/1)
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

  defp write_temp_file(content, extension) do
    tmp_dir = System.tmp_dir!()
    filename = "minizinc_#{:rand.uniform(1_000_000)}#{extension}"
    path = Path.join(tmp_dir, filename)
    File.write!(path, content)
    path
  end
end

