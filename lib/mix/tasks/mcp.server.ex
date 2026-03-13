# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule Mix.Tasks.Mcp.Server do
  @moduledoc """
  Mix task to run the MCP MiniZinc server.

  This task starts the MCP server that provides MiniZinc constraint programming
  capabilities via the Model Context Protocol.

  ## Usage

      mix mcp.server

  The server listens on HTTP (streaming). Set PORT (default 8081) and HOST. Runs until stopped.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    # Start the MCP application
    Application.ensure_all_started(:minizinc_mcp)

    # Keep the process running
    Process.sleep(:infinity)
  end
end
