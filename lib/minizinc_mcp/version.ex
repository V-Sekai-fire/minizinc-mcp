# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.Version do
  @moduledoc """
  Version information for MiniZinc MCP Server.
  
  This module provides a timeless interface for version information,
  reading from application metadata set at compile time from mix.exs.
  """

  # MCP Protocol version - this is the protocol specification version, not the server version
  # This should only change when the MCP protocol itself changes
  @mcp_protocol_version "2025-06-18"

  # Get version at compile time from Mix.Project
  # This allows the version to be used in compile-time macros like `use ExMCP.Server`
  @compile_time_version Mix.Project.config()[:version] || "unknown"

  @doc """
  Returns the application version from mix.exs.
  At compile time, this uses Mix.Project.config().
  At runtime, this reads from Application metadata.
  """
  @spec server_version() :: String.t()
  def server_version do
    # Try runtime first (for releases where Mix is not available)
    case Application.spec(:minizinc_mcp, :vsn) do
      nil ->
        # Fallback to compile-time version if available
        @compile_time_version

      version ->
        # Convert charlist to string
        List.to_string(version)
    end
  end

  @doc """
  Returns the compile-time version constant.
  Use this for compile-time macros that need a constant value.
  """
  @spec compile_time_version() :: String.t()
  def compile_time_version, do: @compile_time_version

  @doc """
  Returns the MCP protocol version.
  This is the protocol specification version, not the server version.
  """
  @spec protocol_version() :: String.t()
  def protocol_version, do: @mcp_protocol_version

  @doc """
  Returns server info map with name and version.
  """
  @spec server_info() :: %{name: String.t(), version: String.t()}
  def server_info do
    %{
      name: "MiniZinc MCP Server",
      version: server_version()
    }
  end
end

