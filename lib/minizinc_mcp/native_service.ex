# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.NativeService do
  @moduledoc """
  Native BEAM service for MiniZinc MCP using ex_mcp library.
  Provides MiniZinc constraint programming tools via MCP protocol.

  This server provides tools for:
  - Solving MiniZinc models (using chuffed solver only)

  ## Output Format

  Supports both MZN (model) and DZN (data) content as strings.

  **Solution Output:**
  - **DZN format**: When available, variables are parsed from DZN format and returned as structured data
  - **Output text**: Explicit `output` statements are passthrough'd in the `output_text` field
  - **Both**: When both formats are available, both are included in the response

  Only DZN format is parsed for variable extraction. Output text from explicit `output` statements
  is always included when available, even if DZN format is not present.
  """

  # Suppress warnings from ex_mcp DSL generated code
  @compile {:no_warn_undefined, :no_warn_pattern}

  use ExMCP.Server,
    name: "MiniZinc MCP Server",
    version: "1.0.0"

  alias MiniZincMcp.Solver

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  # Override do_start_link to start without name when no name is provided
  # This prevents conflicts when ExMCP.MessageProcessor starts temporary instances
  # MessageProcessor now handles :already_started gracefully
  defp do_start_link(:native, opts) do
    name = Keyword.get(opts, :name)

    # Only register name if explicitly provided
    # When ExMCP.MessageProcessor calls start_link([]), no name is provided,
    # so we start without name registration to avoid conflicts
    genserver_opts = if name, do: [name: name], else: []

    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  # Define MiniZinc tools using ex_mcp DSL

  deftool "minizinc_solve" do
    meta do
      name("Solve MiniZinc Model")

      description("""
      Solves a MiniZinc model file or string content using chuffed solver (fixed, not configurable).

      Standard libraries: By default, automatically includes common MiniZinc standard libraries (e.g., alldifferent.mzn) 
      if not already present in the model. This can be controlled via the auto_include_stdlib parameter (default: true).
      This allows models to use standard functions without explicit includes.

      Output format:
      - DZN format: Variables are parsed from DZN format when available (models without explicit output statements)
      - Output text: Explicit output statements are passthrough'd in output_text field
      - Both formats are included when available
      """)
    end

    input_schema(%{
      type: "object",
      properties: %{
        model_path: %{
          type: "string",
          description: "Path to .mzn MiniZinc model file (or use model_content for string)"
        },
        model_content: %{
          type: "string",
          description: "MiniZinc model content (.mzn) as string (alternative to model_path)"
        },
        data_path: %{
          type: "string",
          description: "Optional path to .dzn data file (alternative to data_content)"
        },
        data_content: %{
          type: "string",
          description:
            "Optional .dzn data content as string. Must be valid DZN format (e.g., 'n = 8;'). Parsed and included in response."
        },
        timeout: %{
          type: "integer",
          description: "Optional timeout in milliseconds (default: no timeout, runs indefinitely)"
        },
        auto_include_stdlib: %{
          type: "boolean",
          description:
            "Automatically include standard MiniZinc libraries (e.g., alldifferent.mzn) if not present (default: true)",
          default: true
        }
      }
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: false
    })
  end

  # Initialize handler
  @impl true
  def handle_initialize(params, state) do
    {:ok,
     %{
       protocolVersion: Map.get(params, "protocolVersion", "2025-06-18"),
       serverInfo: %{
         name: "MiniZinc MCP Server",
         version: "1.0.0"
       },
       capabilities: %{
         tools: %{},
         resources: %{},
         prompts: %{}
       }
     }, state}
  end

  # Tool call handlers
  @impl true
  def handle_tool_call(tool_name, args, state) do
    case tool_name do
      "minizinc_solve" ->
        handle_solve(args, state)

      _ ->
        {:error, "Tool not found: #{tool_name}", state}
    end
  end

  defp handle_solve(args, state) do
    # Ensure args is a map
    args = if is_map(args), do: args, else: %{}

    model_path = Map.get(args, "model_path")
    model_content = Map.get(args, "model_content")
    data_path = Map.get(args, "data_path")
    data_content = Map.get(args, "data_content")
    # Only allow chuffed solver (ignore user input)
    solver = "chuffed"
    timeout = Map.get(args, "timeout", :infinity)
    auto_include_stdlib = Map.get(args, "auto_include_stdlib", true)

    opts = [solver: solver, timeout: timeout, auto_include_stdlib: auto_include_stdlib]

    try do
      result =
        cond do
          model_content && model_content != "" ->
            # Solve from string content
            Solver.solve_string(model_content, data_content, opts)

          model_path && model_path != "" ->
            # Solve from file
            Solver.solve(model_path, data_path, opts)

          true ->
            {:error, "Either model_path or model_content must be provided"}
        end

      case result do
        {:ok, solution} ->
          # Ensure all keys are strings for JSON encoding
          # Recursively convert atom keys to strings
          solution_map = normalize_for_json(solution)
          
          # Encode to JSON, handling encoding errors gracefully
          case Jason.encode(solution_map) do
            {:ok, solution_json} ->
              # Create content item with string keys for JSON compatibility
              content_item = %{"type" => "text", "text" => solution_json}
              response = %{"content" => [content_item]}
              {:ok, response, state}
              
            {:error, encode_error} ->
              # If JSON encoding fails, return error instead of crashing
              error_msg = "Failed to encode solution to JSON: #{inspect(encode_error)}"
              {:error, error_msg, state}
          end

        {:error, reason} ->
          # Preserve full error message from solver
          # ex_mcp uses inspect() which will double-encode if reason contains JSON
          # Ensure reason is a plain string (not JSON) to avoid double encoding
          error_msg = if is_binary(reason), do: reason, else: to_string(reason)
          # If error_msg looks like it contains JSON, try to extract and format it properly
          # to avoid double encoding when ex_mcp calls inspect() on it
          # ex_mcp uses inspect() which will quote strings, so we need plain text, not JSON
          final_error_msg = 
            if String.contains?(error_msg, "\"type\": \"error\"") or 
               String.contains?(error_msg, "{\"type\":\"error\"") or
               String.contains?(error_msg, "\"type\":\"error\"") do
              # Error message contains raw JSON, extract and format it as plain string
              case extract_and_format_error_from_string(error_msg) do
                formatted when is_binary(formatted) and formatted != "" -> formatted
                _ -> 
                  # Fallback: try to extract from the raw output that might be embedded
                  # Look for the actual error JSON and format it
                  extract_error_from_error_message(error_msg)
              end
            else
              error_msg
            end
          {:error, final_error_msg, state}
      end
    rescue
      e ->
        # Catch any unexpected exceptions and return as error message
        error_msg = "MiniZinc solve error: #{inspect(e)}"
        {:error, error_msg, state}
    catch
      :exit, reason ->
        # Catch exit signals and return as error message
        error_msg = "MiniZinc solve exited: #{inspect(reason)}"
        {:error, error_msg, state}
      kind, reason ->
        # Catch any other thrown values
        error_msg = "MiniZinc solve error (#{inspect(kind)}): #{inspect(reason)}"
        {:error, error_msg, state}
    end
  end

  # Recursively convert atom keys to strings for JSON encoding
  defp normalize_for_json(value) when is_map(value) do
    Enum.reduce(value, %{}, fn
      {k, v}, acc when is_atom(k) ->
        Map.put(acc, Atom.to_string(k), normalize_for_json(v))

      {k, v}, acc ->
        Map.put(acc, k, normalize_for_json(v))
    end)
  end

  defp normalize_for_json(value) when is_list(value) do
    Enum.map(value, &normalize_for_json/1)
  end

  defp normalize_for_json(value), do: value

  # Extract and format error from string that may contain JSON
  # Decode JSON into Elixir terms, then format as plain string (not JSON)
  defp extract_and_format_error_from_string(error_str) when is_binary(error_str) do
    # Try to find JSON error objects in the string using parser (no regex)
    alias MiniZincMcp.Solver
    
    # First try to parse the entire string as JSON
    case Jason.decode(error_str) do
      {:ok, %{"type" => "error"} = error_json} ->
        Solver.build_error_message(error_json)
      _ ->
        # Try to extract JSON objects from the string
        json_objects = extract_json_objects_from_string(error_str)
        
        Enum.reduce(json_objects, "", fn json_str, acc ->
          case Jason.decode(json_str) do
            {:ok, %{"type" => "error"} = error_json} ->
              error_msg = Solver.build_error_message(error_json)
              if acc == "", do: error_msg, else: acc <> "\n\n" <> error_msg
            _ ->
              acc
          end
        end)
    end
  end

  defp extract_and_format_error_from_string(_), do: nil

  # Fallback: extract error from error message string that contains JSON
  defp extract_error_from_error_message(error_msg) when is_binary(error_msg) do
    # The error message might contain escaped JSON (from inspect() or similar)
    # Try to extract JSON objects from the error message
    json_objects = extract_json_objects_from_string(error_msg)
    
    # Try to find error JSON and format it
    result = Enum.reduce(json_objects, nil, fn json_str, acc ->
      case Jason.decode(json_str) do
        {:ok, %{"type" => "error"} = error_json} ->
          # Found error JSON, format it as plain string
          alias MiniZincMcp.Solver
          formatted = Solver.build_error_message(error_json)
          if formatted != "" and formatted != nil, do: formatted, else: acc
        _ ->
          acc
      end
    end)
    
    # If we found a formatted error, return it; otherwise return original
    if result != nil and result != "" do
      result
    else
      error_msg
    end
  end

  defp extract_error_from_error_message(_), do: nil

  # Extract JSON objects from string using parser (no regex)
  defp extract_json_objects_from_string(text) when is_binary(text) do
    find_json_objects_in_string(text, 0, [], [])
  end

  defp find_json_objects_in_string(<<>>, _, _, acc), do: Enum.reverse(acc)
  
  defp find_json_objects_in_string(<<"{", rest::binary>>, depth, current, acc) do
    find_json_objects_in_string(rest, depth + 1, ["{" | current], acc)
  end
  
  defp find_json_objects_in_string(<<"}", rest::binary>>, 1, current, acc) do
    json_str = Enum.reverse(["}" | current]) |> Enum.join("")
    find_json_objects_in_string(rest, 0, [], [json_str | acc])
  end
  
  defp find_json_objects_in_string(<<"}", rest::binary>>, depth, current, acc) when depth > 1 do
    find_json_objects_in_string(rest, depth - 1, ["}" | current], acc)
  end
  
  defp find_json_objects_in_string(<<char, rest::binary>>, depth, current, acc) when depth > 0 do
    find_json_objects_in_string(rest, depth, [<<char>> | current], acc)
  end
  
  defp find_json_objects_in_string(<<_char, rest::binary>>, 0, _current, acc) do
    find_json_objects_in_string(rest, 0, [], acc)
  end
end
