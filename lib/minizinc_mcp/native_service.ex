# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.NativeService do
  @moduledoc """
  Native BEAM service for MiniZinc MCP using ex_mcp library.
  Provides MiniZinc constraint programming tools via MCP protocol.

  This server provides tools for:
  - Solving MiniZinc models
  - Listing available solvers
  - Checking MiniZinc availability
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
      description("Solves a MiniZinc model file or string content")
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
        solver: %{
          type: "string",
          description: "Solver name (only 'chuffed' is supported)",
          default: "chuffed",
          enum: ["chuffed"]
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

  deftool "minizinc_list_solvers" do
    meta do
      name("List Available Solvers")
      description("Lists all available MiniZinc solvers")
    end

    input_schema(%{
      type: "object",
      properties: %{}
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
    })
  end

  deftool "minizinc_check_available" do
    meta do
      name("Check MiniZinc Availability")
      description("Checks if MiniZinc is available on the system")
    end

    input_schema(%{
      type: "object",
      properties: %{}
    })

    tool_annotations(%{
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true
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

      "minizinc_list_solvers" ->
        handle_list_solvers(state)

      "minizinc_check_available" ->
        handle_check_available(state)

      _ ->
        {:error, "Tool not found: #{tool_name}", state}
    end
  end

  defp handle_solve(args, state) do
    model_path = args["model_path"]
    model_content = args["model_content"]
    data_path = args["data_path"]
    data_content = args["data_content"]
    solver_input = Map.get(args, "solver", "chuffed")
    # Only allow chuffed solver
    solver = if solver_input == "chuffed", do: "chuffed", else: "chuffed"
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

  defp handle_list_solvers(state) do
    case Solver.list_solvers() do
      {:ok, solvers} ->
        solvers_json = Jason.encode!(solvers)
        {:ok, %{content: [text(solvers_json)]}, state}

      {:error, reason} ->
        {:error, "Failed to list solvers: #{reason}", state}
    end
  end

  defp handle_check_available(state) do
    available = Solver.available?()
    result = %{available: available}
    result_json = Jason.encode!(result)
    {:ok, %{content: [text(result_json)]}, state}
  end
end
