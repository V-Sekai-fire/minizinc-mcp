# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Router do
  @moduledoc """
  Router for MiniZinc MCP HTTP server.
  Adds health check endpoint and forwards MCP requests to ExMCP.HttpPlug.
  """

  use Plug.Router

  plug :match
  plug :dispatch

  # Health check endpoint for Docker/Smithery
  get "/health" do
    send_resp(conn, 200, Jason.encode!(%{status: "ok"}))
  end

  # Forward all other requests to HttpPlugWrapper (which fixes SSE fallback)
  forward "/",
    to: MiniZincMcp.HttpPlugWrapper,
    init_opts: [
      handler: MiniZincMcp.NativeService,
      server_info: %{
        name: "MiniZinc MCP Server",
        version: "1.0.0"
      },
      # Always enable SSE (never disable), but HttpPlugWrapper will fallback to HTTP if no SSE connection
      # Set MCP_SSE_ENABLED=false to disable SSE entirely (not recommended)
      sse_enabled: System.get_env("MCP_SSE_ENABLED") != "false",
      cors_enabled: true
    ]
end

