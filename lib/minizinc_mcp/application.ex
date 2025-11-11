# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Application do
  @moduledoc false

  use Application

  @spec start(:normal | :permanent | :transient, any()) :: {:ok, pid()}
  @impl true
  def start(_type, _args) do
    # Determine transport based on environment
    transport = get_transport()

    children =
      case transport do
        :http ->
          port = get_port()
          host = get_host()

          # For HTTP transport, don't start NativeService as supervisor child
          # MessageProcessor will manage server instances per request
          # Only start HttpServer (which uses Router with health check)
          [
            {MiniZincMcp.HttpServer, [port: port, host: host]}
          ]

        :stdio ->
          # For stdio transport, start NativeService as supervisor child
          [
            {MiniZincMcp.NativeService, [name: MiniZincMcp.NativeService]},
            {MiniZincMcp.StdioServer, []}
          ]
      end

    opts = [strategy: :one_for_one, name: MiniZincMcp.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_port do
    case System.get_env("PORT") do
      nil -> 8081
      port_str -> String.to_integer(port_str)
    end
  end

  defp get_host do
    # Use 0.0.0.0 for Docker/container deployments to accept external connections
    # Use localhost for local development
    case System.get_env("HOST") do
      nil ->
        # Default to 0.0.0.0 if PORT is set (container deployment), otherwise localhost
        if System.get_env("PORT"), do: "0.0.0.0", else: "localhost"

      host ->
        host
    end
  end

  defp get_transport do
    case System.get_env("MCP_TRANSPORT") do
      "http" ->
        :http

      "stdio" ->
        :stdio

      _ ->
        # Default to http if PORT is set (Smithery deployment), otherwise stdio
        if System.get_env("PORT"), do: :http, else: :stdio
    end
  end
end

