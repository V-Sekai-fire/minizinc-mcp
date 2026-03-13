# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Application do
  @moduledoc """
  Application supervisor for MiniZinc MCP Server.
  Starts HTTP streaming transport only (no stdio). Use PORT / HOST to configure.
  """

  use Application

  @spec start(:normal | :permanent | :transient, any()) :: {:ok, pid()}
  @impl true
  def start(_type, _args) do
    port = get_port()
    host = get_host()

    children = [
      {MiniZincMcp.NativeService, [name: MiniZincMcp.NativeService]},
      {MiniZincMcp.HttpServer, [port: port, host: host]}
    ]

    opts = [
      strategy: :one_for_one,
      name: MiniZincMcp.Supervisor,
      max_restarts: 10,
      max_seconds: 60
    ]

    Supervisor.start_link(children, opts)
  end

  defp get_port do
    case System.get_env("PORT") do
      nil -> 8081
      port_str -> String.to_integer(port_str)
    end
  rescue
    ArgumentError -> 8081
  end

  defp get_host do
    case System.get_env("HOST") do
      nil -> if System.get_env("PORT"), do: "0.0.0.0", else: "localhost"
      host -> host
    end
  end
end
