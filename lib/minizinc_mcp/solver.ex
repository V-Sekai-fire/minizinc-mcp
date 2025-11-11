# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Solver do
  @moduledoc """
  MiniZinc solver using System.cmd to call minizinc command-line tool with JSON output.

  This solver uses the standard MiniZinc command-line interface and parses JSON output.
  No NIFs are required - everything is done via external process communication.

  ## Standard Library Preamble

  The solver automatically adds standard MiniZinc library includes (e.g., `alldifferent.mzn`) 
  to models if they are not already present. This allows models to use standard functions like 
  `all_different` without requiring explicit `include` statements.

  ## Output Format

  The solver handles two output formats from MiniZinc:

  1. **DZN format**: When MiniZinc provides DZN format output (models without explicit `output` statements),
     variables are parsed and returned as structured data (e.g., `{"x": 10, "y": [1, 2, 3]}`).

  2. **Output text**: When models include explicit `output` statements, the output text is passthrough'd
     in the `output_text` field (e.g., `{"output_text": "x = 10\n"}`).

  Only DZN format is parsed for variable extraction. Output text from explicit `output` statements
  is always included when available, even if DZN format is not present.
  """

  require Logger

  @doc """
  Solves a MiniZinc model file using the minizinc command-line tool with chuffed solver.

  ## Parameters

  - `model_path`: Path to .mzn MiniZinc model file
  - `data_path`: Optional path to .dzn data file
  - `opts`: Options keyword list
    - `:timeout` - Optional timeout in milliseconds (default: :infinity, no timeout)
    - `:solver_options` - Additional solver options

  Note: Only chuffed solver is supported.

  ## Returns

  - `{:ok, solution}` - Solution map containing:
    - Parsed variables from DZN format (when available)
    - `output_text` field with explicit output statement text (when available)
    - `dzn_output` field with raw DZN format text (when available)
    - `output` field with raw MiniZinc output structure
    - `input_data` field with parsed input DZN data (when provided)
  - `{:error, reason}` - Error reason
  """
  @spec solve(String.t(), String.t() | nil, keyword()) :: {:ok, map()} | {:error, String.t()}
  def solve(model_path, data_path \\ nil, opts \\ []) do
    # Only support chuffed solver
    solver = "chuffed"
    timeout = Keyword.get(opts, :timeout, :infinity)
    solver_options = Keyword.get(opts, :solver_options, [])

    if File.exists?(model_path) do
      build_and_run_command(model_path, data_path, solver, timeout, solver_options)
    else
      {:error, "MiniZinc model file not found: #{model_path}"}
    end
  end

  @doc """
  Solves MiniZinc model from string content.

  Writes the content to a temporary file and solves it.

  ## Parameters

  - `model_content`: MiniZinc model content as string
  - `data_content`: Optional DZN data content as string (parsed and included in response as `input_data`)
  - `opts`: Options keyword list (same as solve/3)

  ## Returns

  Same as solve/3. The `input_data` field contains parsed DZN data when `data_content` is provided.
  """
  @spec solve_string(String.t(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, String.t()}
  def solve_string(model_content, data_content \\ nil, opts \\ []) do
    # Parse DZN data content if provided
    parsed_data = if data_content, do: parse_dzn_output(data_content), else: %{}

    # Add standard library preamble if enabled and not already present
    auto_include = Keyword.get(opts, :auto_include_stdlib, true)
    # Trim leading whitespace/newlines before processing
    trimmed_model = String.trim_leading(model_content)

    model_with_preamble =
      if auto_include, do: add_standard_preamble(trimmed_model), else: trimmed_model

    case Briefly.create(prefix: "minizinc_") do
      {:ok, model_file_base} ->
        # Briefly doesn't add extensions, so we need to add it manually
        model_file = model_file_base <> ".mzn"

        # Write model file, handling errors without exceptions
        case File.write(model_file, model_with_preamble) do
          :ok ->
            # Verify file exists and is readable
            if File.exists?(model_file) do
              # Create data file if needed
              case maybe_create_data_file(data_content) do
                {:ok, created_data_file} ->
                  data_file = created_data_file
                  result = solve(model_file, data_file, opts)
                  
                  # Clean up temporary files
                  cleanup_file(model_file)
                  cleanup_file(data_file)
                  
                  case result do
                    {:ok, solution} ->
                      # Merge parsed input data into solution for reference
                      solution_with_data = Map.merge(solution, %{input_data: parsed_data})
                      {:ok, solution_with_data}

                    error ->
                      error
                  end
                  
                {:error, reason} ->
                  cleanup_file(model_file)
                  {:error, "Failed to create data file: #{reason}"}
                  
                nil ->
                  # No data file needed
                  result = solve(model_file, nil, opts)
                  
                  # Clean up temporary files
                  cleanup_file(model_file)
                  
                  case result do
                    {:ok, solution} ->
                      # Merge parsed input data into solution for reference
                      solution_with_data = Map.merge(solution, %{input_data: parsed_data})
                      {:ok, solution_with_data}

                    error ->
                      error
                  end
              end
            else
              cleanup_file(model_file)
              {:error, "Temporary file was not created: #{model_file}"}
            end

          {:error, reason} ->
            {:error, "Failed to write temporary file: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to create temporary file: #{inspect(reason)}"}
    end
  end

  defp add_standard_preamble(model_content) do
    # Standard MiniZinc library includes that are commonly needed
    standard_includes = [
      "include \"alldifferent.mzn\";"
    ]

    # Check if model already includes any of these
    has_include =
      Enum.any?(standard_includes, fn include ->
        String.contains?(model_content, include)
      end)

    if has_include do
      # Model already has includes, don't add preamble
      model_content
    else
      # Add standard preamble at the beginning
      preamble = Enum.join(standard_includes, "\n") <> "\n\n"
      preamble <> model_content
    end
  end

  defp maybe_create_data_file(nil), do: nil

  defp maybe_create_data_file(data_content) do
    case Briefly.create(prefix: "minizinc_") do
      {:ok, data_file_base} ->
        # Briefly doesn't add extensions, so we need to add it manually
        data_file = data_file_base <> ".dzn"
        
        case File.write(data_file, data_content) do
          :ok ->
            # Verify file exists
            if File.exists?(data_file) do
              {:ok, data_file}
            else
              {:error, "Data file was not created: #{data_file}"}
            end

          {:error, reason} ->
            {:error, "Failed to write data file: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, "Failed to create data file: #{inspect(reason)}"}
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
    task =
      Task.async(fn ->
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
      task =
        Task.async(fn ->
          System.cmd("minizinc", cmd_args, stderr_to_stdout: true)
        end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, {output, 0}} ->
          parse_output(output)

        {:ok, {output, exit_status}} ->
          # Log full output for debugging (both stdout and stderr are captured via stderr_to_stdout)
          Logger.debug(
            "MiniZinc returned exit status #{exit_status}, output length: #{String.length(output)}"
          )

          Logger.debug("MiniZinc raw output: #{inspect(output)}")

          # Always try to parse output first, regardless of exit status
          # MiniZinc may return valid JSON with status "UNSATISFIABLE" even with non-zero exit code
          # Without --json-stream, MiniZinc outputs DZN format or plain text
          case parse_output(output) do
            {:ok, solution} ->
              # Successfully parsed - return the solution even if exit status was non-zero
              # Check if solution contains a status that indicates an error
              case Map.get(solution, "status") do
                status when status in ["UNSATISFIABLE", "UNSAT"] ->
                  # These are valid results, not errors
                  {:ok, solution}
                _ ->
                  {:ok, solution}
              end

            {:error, error_msg} ->
              # parse_output found a MiniZinc error and formatted it
              # Return the formatted error message directly (already plain string, not JSON)
              Logger.error(
                "MiniZinc error (exit status #{exit_status}): #{error_msg}"
              )
              {:error, error_msg}

            other ->
              # Unexpected return from parse_output
              # Check what was actually returned and handle it appropriately
              Logger.error("Unexpected return from parse_output: #{inspect(other)}")
              
              # Try to extract error from raw output and format it as plain string (no JSON)
              # This avoids including raw JSON in error messages
              formatted_error = extract_error_from_raw_output(output)
              
              # If it's actually an ok tuple, return it
              case other do
                {:ok, result} when is_map(result) ->
                  # Check status in result
                  case Map.get(result, "status") do
                    nil -> {:ok, result}
                    status -> {:ok, result}
                  end
                _ ->
                  # Not a recognized format
                  # If we extracted a formatted error, use it; otherwise return simple error
                  # NEVER include raw output in error messages - always format as plain string
                  if formatted_error != "" and formatted_error != nil do
                    {:error, formatted_error}
                  else
                    # Return simple error without any raw output
                    {:error, "MiniZinc failed with exit status #{exit_status}"}
                  end
              end
          end

        nil ->
          if timeout == :infinity do
            {:error, "MiniZinc execution was interrupted"}
          else
            {:error, "MiniZinc execution timed out after #{timeout}ms"}
          end

        {:exit, reason} ->
          {:error, "MiniZinc process exited: #{inspect(reason)}"}
      end
    rescue
      e -> {:error, "MiniZinc execution error: #{inspect(e)}"}
    end
  end

  defp build_command_args(model_path, data_path, solver, solver_options) do
    args = [
      "--solver",
      solver,
      "--canonicalize"
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

  defp cleanup_file(nil), do: :ok

  defp cleanup_file(file_path) do
    if File.exists?(file_path) do
      File.rm(file_path)
      Logger.debug("Cleaned up temporary file: #{file_path}")
    end
  rescue
    e -> Logger.warning("Failed to cleanup file #{file_path}: #{inspect(e)}")
  end

  defp parse_output(output) do
    # Parse MiniZinc output (JSON, DZN format, or plain text errors)
    # Handle non-binary output
    output_str = if is_binary(output), do: output, else: inspect(output)

    # MiniZinc can output:
    # 1. JSON format (with --json-stream): newline-delimited JSON objects
    # 2. DZN format (without --json-stream): "x = 9;\n----------\n"
    # 3. Plain text errors: "/path/file.mzn:line.col:\nError: message"
    # 4. Status messages: "=====UNSATISFIABLE====="
    
    # First try simple line-by-line parsing (most common case for JSON)
    lines = String.split(output_str, "\n") |> Enum.filter(&(&1 != ""))
    
    # Check if any line contains valid JSON
    has_json = Enum.any?(lines, fn line ->
      case Jason.decode(line) do
        {:ok, _} -> true
        _ -> false
      end
    end)
    
    # If no valid JSON lines found, handle plain text output
    # (Without --json-stream, MiniZinc outputs DZN format or plain text)
    {lines, early_error, early_result} = if not has_json do
      # Try extracting JSON objects from text (for backwards compatibility)
      json_objects = extract_json_objects_from_text(output_str)
      
      # If still no JSON found, check for plain text output (DZN or errors)
      if json_objects == [] do
        # Check for plain text errors first
        plain_text_error = extract_error_from_raw_output(output_str)
        if plain_text_error != "" and plain_text_error != nil do
          {[], {:error, plain_text_error}, nil}
        else
          # Check for DZN format output or UNSATISFIABLE status
          # DZN format: "x = 9;\n----------" or similar
          # UNSATISFIABLE: "=====UNSATISFIABLE====="
          if String.contains?(output_str, "=====UNSATISFIABLE=====") do
            {[], nil, {:ok, %{"status" => "UNSATISFIABLE", "message" => "Problem is unsatisfiable - no solution exists"}}}
          else
            # Try to parse as DZN format
            dzn_parsed = parse_dzn_output(output_str)
            if map_size(dzn_parsed) > 0 do
              # Found DZN solution
              solution_map = dzn_parsed
                |> Map.put(:dzn_output, output_str)
                |> Map.put(:output_text, output_str)
              {[], nil, {:ok, solution_map}}
            else
              {[], nil, nil}
            end
          end
        end
      else
        # We found JSON objects, use them
        {json_objects, nil, nil}
      end
    else
      {lines, nil, nil}
    end
    
    # If we detected a plain text error or result early, return it immediately
    if early_error != nil do
      early_error
    else
      if early_result != nil do
        early_result
      else
      # Continue with JSON parsing
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
                atom_keys =
                  json_solution |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end) |> Map.new()

                string_keys = json_solution
                merged = Map.merge(sol_acc, atom_keys) |> Map.merge(string_keys)
                {merged, stat_acc, err_acc}

              %{"type" => "solution", "json" => json_solution} when is_list(json_solution) ->
                # JSON solution as list (array of solutions)
                {Map.merge(sol_acc, %{solutions: json_solution}), stat_acc, err_acc}

              %{"type" => "solution", "output" => output_text} ->
                # Only parse DZN format, but passthrough all output text
                dzn_text = extract_dzn_output(output_text)
                output_text_str = extract_output_text_for_passthrough(output_text)

                if dzn_text != "" do
                  parsed = parse_dzn_output(dzn_text)
                  # Build solution map with parsed variables and DZN output
                  merged =
                    sol_acc
                    |> Map.merge(parsed)
                    |> Map.put(:output, output_text)
                    |> Map.put(:dzn_output, dzn_text)
                    |> maybe_put_output_text(output_text_str)

                  {merged, stat_acc, err_acc}
                else
                  # No DZN output available - passthrough output text without parsing
                  Logger.warning(
                    "Solution has no DZN output format, only: #{inspect(Map.keys(output_text))}"
                  )

                  merged =
                    sol_acc
                    |> Map.put(:output, output_text)
                    |> maybe_put_output_text(output_text_str)

                  {merged, stat_acc, err_acc}
                end

              %{"type" => "status", "status" => stat} ->
                {sol_acc, stat, err_acc}

              %{"type" => "error"} = error_json ->
                # Extract all error details for debugging
                # MiniZinc error JSON can have: message, what, location, etc.
                error_details = build_error_message(error_json)
                Logger.debug("Found MiniZinc error JSON: #{inspect(error_json)}, formatted: #{inspect(error_details)}")
                {sol_acc, stat_acc, error_details}

              %{"type" => "solution"} ->
                # Solution without json or output field - might have variables directly
                solution_vars = Map.drop(json, ["type"])
                {Map.merge(sol_acc, solution_vars), stat_acc, err_acc}

              _ ->
                {sol_acc, stat_acc, err_acc}
            end

          {:error, decode_error} ->
            # If JSON decode fails, log and skip (don't fall back to text parsing)
            Logger.warning(
              "Failed to parse JSON line: #{inspect(line)} - #{inspect(decode_error)}"
            )

            {sol_acc, stat_acc, err_acc}
          end
        end)

      # Return appropriate result
      # ALWAYS prioritize errors - if an error was found, return it immediately
      Logger.debug("parse_output result: error=#{inspect(error)}, error_is_binary=#{is_binary(error)}, status=#{inspect(status)}, solution_size=#{map_size(solution)}")
      cond do
        error != nil && error != "" ->
          Logger.error("MiniZinc error: #{inspect(error)}")
          # Error is already formatted by build_error_message, but ensure it's a string
          error_msg = if is_binary(error), do: error, else: inspect(error)
          {:error, error_msg}

        status in ["UNSATISFIABLE", "UNSAT"] ->
        # UNSATISFIABLE is a valid result - the problem has no solution
        # Use string keys for JSON compatibility
        Logger.info("Problem is unsatisfiable (status: #{inspect(status)})")
        {:ok, %{"status" => status, "message" => "Problem is unsatisfiable - no solution exists"}}

        status == "OPTIMAL_SOLUTION" or status == "SATISFIED" ->
          if map_size(solution) > 0 do
            {:ok, solution}
          else
            # Use string keys for JSON compatibility
            {:ok, %{"status" => status}}
          end

        map_size(solution) > 0 ->
          {:ok, solution}

        status != nil ->
          # We have a status but no solution - return it as success with status
          # Use string keys for JSON compatibility
          Logger.info(
            "No solution found. Status: #{inspect(status)}, Solution map: #{inspect(solution)}"
          )

          {:ok, %{"status" => status, "solution" => solution}}

        true ->
          # If we have no solution and no clear status, check for plain text errors
          # before returning generic error message
          plain_text_error = extract_error_from_raw_output(output_str)
          
          if plain_text_error != "" and plain_text_error != nil do
            {:error, plain_text_error}
          else
            Logger.warning(
              "No solution found and no clear status. Solution map: #{inspect(solution)}, Status: #{inspect(status)}, Error: #{inspect(error)}"
            )
            {:error, "No solution found. Status: #{inspect(status)}"}
          end
      end
    end
    end
  end

  def build_error_message(error_json) when is_map(error_json) do
    # Extract all available error information for debugging
    # Decode JSON into Elixir terms, then format as plain string (not JSON)
    # This ensures it only gets JSON-encoded once by the MCP protocol
    message = Map.get(error_json, "message", "")
    what = Map.get(error_json, "what", "")
    location = Map.get(error_json, "location", %{})
    
    # Build location string if available
    location_str = build_location_string(location)
    
    # Build comprehensive error message as plain string (not JSON)
    parts = []
    
    parts = if what != "", do: ["Error type: #{what}" | parts], else: parts
    parts = if message != "", do: ["Message: #{message}" | parts], else: parts
    parts = if location_str != "", do: ["Location: #{location_str}" | parts], else: parts
    
    # If we have parts, join them as plain string; otherwise return a simple error message
    if parts != [] do
      Enum.join(Enum.reverse(parts), "\n")
    else
      # Fallback: return a simple error message (not JSON)
      "MiniZinc error occurred"
    end
  end

  def build_error_message(error) when is_binary(error) do
    # If error is already a string, try to parse it as JSON first
    case Jason.decode(error) do
      {:ok, error_json} when is_map(error_json) ->
        build_error_message(error_json)
      _ ->
        error
    end
  end

  def build_error_message(error), do: inspect(error)

  defp build_location_string(location) when is_map(location) do
    filename = Map.get(location, "filename", "")
    first_line = Map.get(location, "firstLine")
    first_column = Map.get(location, "firstColumn")
    last_line = Map.get(location, "lastLine")
    last_column = Map.get(location, "lastColumn")
    
    location_parts = []
    location_parts = if filename != "", do: [filename | location_parts], else: location_parts
    
    if first_line != nil do
      line_col_str = "line #{first_line}"
      line_col_str = if first_column != nil, do: "#{line_col_str}, column #{first_column}", else: line_col_str
      
      if last_line != nil and last_line != first_line do
        line_col_str = "#{line_col_str} to line #{last_line}"
        line_col_str = if last_column != nil, do: "#{line_col_str}, column #{last_column}", else: line_col_str
      end
      
      location_parts = [line_col_str | location_parts]
    end
    
    if location_parts != [] do
      Enum.join(Enum.reverse(location_parts), " at ")
    else
      ""
    end
  end

  defp build_location_string(_), do: ""

  defp extract_error_from_raw_output(output) when is_binary(output) do
    # Without --json-stream, MiniZinc outputs plain text errors, not JSON
    # Format: /path/to/file.mzn:line.column:\ncode\n^\nError: message
    # Try to extract and format plain text errors
    
    lines = String.split(output, "\n") |> Enum.filter(&(&1 != ""))
    
    # Look for error patterns in plain text output
    error_lines = 
      Enum.reduce(lines, [], fn line, acc ->
        cond do
          # Match "Error: ..." pattern
          String.starts_with?(line, "Error:") ->
            [String.trim_leading(line, "Error:") |> String.trim() | acc]
          # Match "error: ..." pattern (lowercase)
          String.starts_with?(String.downcase(line), "error:") ->
            error_msg = line |> String.split(":", parts: 2) |> List.last() |> String.trim()
            [error_msg | acc]
          # Match file location pattern (filename:line.column:)
          String.contains?(line, ":") and Regex.match?(~r/\.mzn:\d+\.\d+:/, line) ->
            # This is a location line, keep it for context
            acc
          true ->
            acc
        end
      end)
    
    # If we found error messages, format them
    if error_lines != [] do
      # Get location context if available
      location_line = Enum.find(lines, fn line -> 
        String.contains?(line, ".mzn:") and Regex.match?(~r/\.mzn:\d+\.\d+:/, line)
      end)
      
      error_msg = Enum.join(Enum.reverse(error_lines), "\n")
      
      if location_line != nil do
        "#{location_line}\n#{error_msg}"
      else
        error_msg
      end
    else
      # Fallback: try to find JSON errors (for backwards compatibility)
      # This handles cases where JSON might still be present
      json_objects = extract_json_objects_from_text(output)
      
      result = Enum.reduce(json_objects, "", fn json_str, acc ->
        case Jason.decode(json_str) do
          {:ok, %{"type" => "error"} = error_json} ->
            error_msg = build_error_message(error_json)
            if acc == "", do: error_msg, else: acc <> "\n\n" <> error_msg
          _ ->
            acc
        end
      end)
      
      # Always return a string (empty string if no error found)
      result
    end
  end

  defp extract_json_objects_from_text(text) do
    # Find all JSON objects in text using parser (no regex)
    # Look for { and } pairs to find JSON boundaries, return list of JSON strings
    find_json_objects(text, 0, [], [])
  end

  defp find_json_objects(<<>>, _, _, acc), do: Enum.reverse(acc)
  
  defp find_json_objects(<<"{", rest::binary>>, depth, current, acc) do
    # Found opening brace, start tracking
    find_json_objects(rest, depth + 1, ["{" | current], acc)
  end
  
  defp find_json_objects(<<"}", rest::binary>>, 1, current, acc) do
    # Found matching closing brace for depth 1, extract JSON string
    json_str = Enum.reverse(["}" | current]) |> Enum.join("")
    find_json_objects(rest, 0, [], [json_str | acc])
  end
  
  defp find_json_objects(<<"}", rest::binary>>, depth, current, acc) when depth > 1 do
    # Found closing brace but not at depth 1, continue tracking
    find_json_objects(rest, depth - 1, ["}" | current], acc)
  end
  
  defp find_json_objects(<<char, rest::binary>>, depth, current, acc) when depth > 0 do
    # Inside a JSON object, continue tracking
    find_json_objects(rest, depth, [<<char>> | current], acc)
  end
  
  defp find_json_objects(<<_char, rest::binary>>, 0, _current, acc) do
    # Not inside a JSON object, skip
    find_json_objects(rest, 0, [], acc)
  end


  defp extract_json_lines_from_text(text) do
    # Extract complete JSON objects from text using parser (no regex)
    # Look for { and } pairs to find JSON boundaries
    extract_json_objects_from_text(text)
    |> Enum.map(fn json_str -> json_str end)
  end

  defp extract_dzn_output(%{"dzn" => text}) when is_binary(text), do: text
  defp extract_dzn_output(_), do: ""

  defp extract_output_text_for_passthrough(output) when is_binary(output), do: output
  defp extract_output_text_for_passthrough(%{"default" => text}) when is_binary(text), do: text
  defp extract_output_text_for_passthrough(%{"raw" => text}) when is_binary(text), do: text

  defp extract_output_text_for_passthrough(output) when is_map(output) do
    # Try to get any string value from the map (prefer default, then raw)
    cond do
      Map.has_key?(output, "default") ->
        output["default"]

      Map.has_key?(output, "raw") ->
        output["raw"]

      true ->
        case Enum.find(output, fn {_, v} -> is_binary(v) end) do
          {_, text} when is_binary(text) -> text
          _ -> nil
        end
    end
  end

  defp extract_output_text_for_passthrough(_), do: nil

  defp maybe_put_output_text(map, nil), do: map

  defp maybe_put_output_text(map, text) when is_binary(text) and text != "",
    do: Map.put(map, :output_text, text)

  defp maybe_put_output_text(map, _), do: map

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
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&remove_comment/1)
    |> Enum.reject(&(&1 == ""))
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
      value_str == "true" ->
        true

      value_str == "false" ->
        false

      # Integer
      Regex.match?(~r/^-?\d+$/, value_str) ->
        String.to_integer(value_str)

      # Float
      Regex.match?(~r/^-?\d+\.\d+$/, value_str) ->
        String.to_float(value_str)

      # String (quoted)
      String.starts_with?(value_str, "\"") and String.ends_with?(value_str, "\"") ->
        String.slice(value_str, 1..-2//-1)

      # Default: return as string
      true ->
        value_str
    end
  end

  defp parse_multidim_array(array_str) do
    # Parse [| 1, 2 | 3, 4 |] format
    # Remove [| and |]
    content =
      array_str
      |> String.slice(2..-3//-1)
      |> String.trim()

    # Split by | to get rows
    rows =
      String.split(content, "|")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))

    Enum.map(rows, fn row ->
      parse_array("[" <> row <> "]")
    end)
  end

  defp parse_set(set_str) do
    # Parse {1, 2, 3} format
    content =
      set_str
      |> String.slice(1..-2//-1)
      |> String.trim()

    case content do
      "" ->
        []

      _ ->
        content
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&parse_dzn_value/1)
        |> Enum.uniq()
        |> Enum.sort()
    end
  end

  defp parse_array(array_str) do
    # Parse [1, 2, 3] format
    content =
      array_str
      |> String.slice(1..-2//-1)
      |> String.trim()

    case content do
      "" ->
        []

      _ ->
        content
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.map(&parse_dzn_value/1)
    end
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
    |> Enum.reject(&(&1 == ""))
  end
end
