# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.StdioServer do
  @moduledoc """
  Stdio-based MCP server that reads JSON-RPC messages from stdin and writes responses to stdout.
  """

  require Logger

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 500
    }
  end

  @spec start_link(term()) :: {:ok, pid()}
  def start_link(opts) do
    # Start the NativeService with stdio transport
    MiniZincMcp.NativeService.start_link(opts ++ [transport: :stdio])
  end
end
