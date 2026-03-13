# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.NativeService do
  @moduledoc """
  MiniZinc MCP tool execution and tool list (no deftool DSL).
  Runs as a named GenServer; MCPHandler calls get_tools/0 and GenServer.call(..., :execute_tool) over HTTP streaming.
  """

  use GenServer
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

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    genserver_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, genserver_opts)
  end

  # Tool list: map of name => %{name, description, input_schema}. Used by MCPHandler.
  @doc false
  def get_tools do
    %{
      "minizinc_solve" => %{
        name: "minizinc_solve",
        description: """
        Solves a MiniZinc model using HiGHS solver (LP/MIP; supports continuous/float variables).

        Standard libraries: By default, automatically includes common MiniZinc standard libraries (e.g., alldifferent.mzn)
        if not already present in the model. This can be controlled via the auto_include_stdlib parameter (default: true).
        This allows models to use standard functions without explicit includes.

        Output format:
        - DZN format: Variables are parsed from DZN format when available (models without explicit output statements)
        - Output text: Explicit output statements are passthrough'd in output_text field
        - Both formats are included when available
        """,
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "model_content" => %{
              "type" => "string",
              "description" => "MiniZinc model content (.mzn) as string"
            },
            "data_content" => %{
              "type" => "string",
              "description" =>
                "Optional .dzn data content as string. Must be valid DZN format (e.g., 'n = 8;'). Parsed and included in response."
            },
            "timeout" => %{
              "type" => "integer",
              "description" =>
                "Optional timeout in milliseconds (default: 30000, i.e., 30 seconds). Maximum allowed is 30000 ms (30 seconds); values exceeding this will be capped at 30 seconds."
            },
            "auto_include_stdlib" => %{
              "type" => "boolean",
              "description" =>
                "Automatically include standard MiniZinc libraries (e.g., alldifferent.mzn) if not present (default: true)",
              "default" => true
            }
          }
        }
      },
      "minizinc_validate" => %{
        name: "minizinc_validate",
        description: """
        Validates a MiniZinc model by checking syntax and type checking without solving.
        Useful for debugging models before attempting to solve them.

        Returns detailed error and warning messages if the model is invalid.
        """,
        input_schema: %{
          "type" => "object",
          "properties" => %{
            "model_content" => %{
              "type" => "string",
              "description" => "MiniZinc model content (.mzn) as string"
            },
            "data_content" => %{
              "type" => "string",
              "description" =>
                "Optional .dzn data content as string. Must be valid DZN format (e.g., 'n = 8;')."
            },
            "auto_include_stdlib" => %{
              "type" => "boolean",
              "description" =>
                "Automatically include standard MiniZinc libraries (e.g., alldifferent.mzn) if not present (default: true)",
              "default" => true
            }
          }
        }
      },
      "minizinc_list_solvers" => %{
        name: "minizinc_list_solvers",
        description: """
        Lists solvers available on this system (e.g. highs, gecode).
        Run this to see which solvers are installed before solving.
        """,
        input_schema: %{
          "type" => "object",
          "properties" => %{},
          "required" => []
        }
      }
    }
  end

  # GenServer
  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:execute_tool, tool_name, arguments}, _from, state) do
    case handle_tool_call(tool_name, arguments, state) do
      {:ok, result, new_state} -> {:reply, {:ok, result}, new_state}
      {:error, reason, new_state} -> {:reply, {:error, reason}, new_state}
    end
  end

  # Called by GenServer for HTTP tool execution.
  def handle_tool_call(tool_name, args, state) do
    case tool_name do
      "minizinc_solve" -> handle_solve(args, state)
      "minizinc_validate" -> handle_validate(args, state)
      "minizinc_list_solvers" -> handle_list_solvers(state)
      _ -> {:error, "Tool not found: #{tool_name}", state}
    end
  end

  defp handle_solve(args, state) do
    args = if is_map(args), do: args, else: %{}
    model_content = Map.get(args, "model_content")
    data_content = Map.get(args, "data_content")
    solver = "highs"
    timeout = min(Map.get(args, "timeout", 30_000), 30_000)
    auto_include_stdlib = Map.get(args, "auto_include_stdlib", true)
    opts = [solver: solver, timeout: timeout, auto_include_stdlib: auto_include_stdlib]

    try do
      result =
        if model_content && model_content != "" do
          Solver.solve_string(model_content, data_content, opts)
        else
          {:error, "model_content must be provided"}
        end

      case result do
        {:ok, solution} ->
          solution_map = normalize_for_json(solution)
          case Jason.encode(solution_map) do
            {:ok, solution_json} ->
              content_item = %{"type" => "text", "text" => solution_json}
              {:ok, %{"content" => [content_item], "isError" => false}, state}
            {:error, encode_error} ->
              {:error, "Failed to encode solution to JSON: #{inspect(encode_error)}", state}
          end

        {:error, reason} ->
          error_msg = if is_binary(reason), do: reason, else: to_string(reason)
          final_error_msg =
            if String.contains?(error_msg, "\"type\": \"error\"") or
                 String.contains?(error_msg, "{\"type\":\"error\"") do
              case extract_and_format_error_from_string(error_msg) do
                formatted when is_binary(formatted) and formatted != "" -> formatted
                _ -> extract_error_from_error_message(error_msg)
              end
            else
              error_msg
            end
          {:error, final_error_msg, state}
      end
    rescue
      e -> {:error, "MiniZinc solve error: #{inspect(e)}", state}
    catch
      :exit, reason -> {:error, "MiniZinc solve exited: #{inspect(reason)}", state}
      kind, reason -> {:error, "MiniZinc solve error (#{inspect(kind)}): #{inspect(reason)}", state}
    end
  end

  defp handle_validate(args, state) do
    args = if is_map(args), do: args, else: %{}
    model_content = Map.get(args, "model_content")
    data_content = Map.get(args, "data_content")
    auto_include_stdlib = Map.get(args, "auto_include_stdlib", true)
    opts = [auto_include_stdlib: auto_include_stdlib]

    try do
      result =
        if model_content && model_content != "" do
          Solver.validate_string(model_content, data_content, opts)
        else
          {:error, "model_content must be provided"}
        end

      case result do
        {:ok, validation_result} ->
          validation_map = normalize_for_json(validation_result)
          case Jason.encode(validation_map) do
            {:ok, validation_json} ->
              content_item = %{"type" => "text", "text" => validation_json}
              {:ok, %{"content" => [content_item], "isError" => false}, state}
            {:error, encode_error} ->
              {:error, "Failed to encode validation result to JSON: #{inspect(encode_error)}", state}
          end
        {:error, reason} ->
          error_msg = if is_binary(reason), do: reason, else: to_string(reason)
          {:error, error_msg, state}
      end
    rescue
      e -> {:error, "MiniZinc validate error: #{inspect(e)}", state}
    catch
      :exit, reason -> {:error, "MiniZinc validate exited: #{inspect(reason)}", state}
      kind, reason -> {:error, "MiniZinc validate error (#{inspect(kind)}): #{inspect(reason)}", state}
    end
  end

  defp handle_list_solvers(state) do
    case Solver.list_solvers() do
      {:ok, solvers} ->
        body = Jason.encode!(%{"solvers" => solvers})
        content = %{"type" => "text", "text" => body}
        {:ok, %{"content" => [content], "isError" => false}, state}
      {:error, reason} ->
        msg = if is_binary(reason), do: reason, else: inspect(reason)
        {:error, msg, state}
    end
  end

  defp normalize_for_json(value) when is_map(value) do
    Enum.reduce(value, %{}, fn
      {k, v}, acc when is_atom(k) -> Map.put(acc, Atom.to_string(k), normalize_for_json(v))
      {k, v}, acc -> Map.put(acc, k, normalize_for_json(v))
    end)
  end

  defp normalize_for_json(value) when is_list(value), do: Enum.map(value, &normalize_for_json/1)
  defp normalize_for_json(value), do: value

  defp extract_and_format_error_from_string(error_str) when is_binary(error_str) do
    case Jason.decode(error_str) do
      {:ok, %{"type" => "error"} = error_json} ->
        Solver.build_error_message(error_json)
      _ ->
        json_objects = extract_json_objects_from_string(error_str)
        Enum.reduce(json_objects, "", fn json_str, acc ->
          case Jason.decode(json_str) do
            {:ok, %{"type" => "error"} = error_json} ->
              msg = Solver.build_error_message(error_json)
              if acc == "", do: msg, else: acc <> "\n\n" <> msg
            _ -> acc
          end
        end)
    end
  end

  defp extract_and_format_error_from_string(_), do: nil

  defp extract_error_from_error_message(error_msg) when is_binary(error_msg) do
    json_objects = extract_json_objects_from_string(error_msg)
    result =
      Enum.reduce(json_objects, nil, fn json_str, acc ->
        case Jason.decode(json_str) do
          {:ok, %{"type" => "error"} = error_json} ->
            formatted = Solver.build_error_message(error_json)
            if formatted != "" and formatted != nil, do: formatted, else: acc
          _ -> acc
        end
      end)
    if result != nil and result != "", do: result, else: error_msg
  end

  defp extract_error_from_error_message(_), do: nil

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
