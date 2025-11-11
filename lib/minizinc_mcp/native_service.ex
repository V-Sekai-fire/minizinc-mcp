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
          description: "Optional .dzn data content as string. Must be valid DZN format (e.g., 'n = 8;'). Parsed and included in response."
        },
        timeout: %{
          type: "integer",
          description: "Timeout in milliseconds (default: 60000)",
          default: 60_000
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
    model_path = args["model_path"]
    model_content = args["model_content"]
    data_path = args["data_path"]
    data_content = args["data_content"]
    # Only allow chuffed solver (ignore user input)
    solver = "chuffed"
    timeout = Map.get(args, "timeout", 60_000)

    opts = [solver: solver, timeout: timeout]

    result =
      cond do
        model_content ->
          # Solve from string content
          Solver.solve_string(model_content, data_content, opts)

        model_path ->
          # Solve from file
          Solver.solve(model_path, data_path, opts)

        true ->
          {:error, "Either model_path or model_content must be provided"}
      end

    case result do
      {:ok, solution} ->
        solution_json = Jason.encode!(solution)
        {:ok, %{content: [text(solution_json)]}, state}

      {:error, reason} ->
        {:error, "Failed to solve model: #{reason}", state}
    end
  end

end
