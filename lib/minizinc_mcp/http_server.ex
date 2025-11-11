# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.HttpServer do
  @moduledoc """
  HTTP server for MiniZinc MCP using ExMCP.HttpPlug.
  Provides HTTP transport for MCP protocol with CORS support.
  """

  require Logger

  @spec child_spec(term()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  @spec start_link(term()) :: {:ok, pid()}
  def start_link(opts) do
    port = get_port(opts)
    host = Keyword.get(opts, :host, "0.0.0.0")

    Logger.info("Starting MiniZinc MCP HTTP server on #{host}:#{port}")

    # Use Router which adds health check endpoint and forwards to ExMCP.HttpPlug
    case Plug.Cowboy.http(MiniZincMcp.Router, [], port: port, ip: parse_host(host)) do
      {:ok, pid} ->
        Logger.info("MiniZinc MCP HTTP server started successfully on port #{port}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.info("MiniZinc MCP HTTP server already running")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start MiniZinc MCP HTTP server: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_port(opts) do
    case Keyword.get(opts, :port) do
      nil ->
        case System.get_env("PORT") do
          nil -> 8081
          port_str -> String.to_integer(port_str)
        end

      port when is_integer(port) ->
        port

      port_str when is_binary(port_str) ->
        String.to_integer(port_str)
    end
  end

  defp parse_host("0.0.0.0"), do: {0, 0, 0, 0}
  defp parse_host("localhost"), do: {127, 0, 0, 1}
  defp parse_host(host) when is_binary(host), do: to_charlist(host)
  defp parse_host(host), do: host
end

