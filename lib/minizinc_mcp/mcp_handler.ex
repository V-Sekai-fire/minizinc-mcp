# SPDX-License-Identifier: MIT
# Copyright (c) 2025-present K. S. Ernest (iFire) Lee

defmodule MiniZincMcp.MCPHandler do
  @moduledoc """
  ExMCP Handler that exposes MiniZinc tools with camelCase inputSchema (like vsekai).
  Delegates tool execution to MiniZincMcp.NativeService.
  """
  use ExMCP.Server.Handler

  def get_capabilities do
    %{
      "tools" => %{"listChanged" => false},
      "resources" => %{"listChanged" => false},
      "prompts" => %{"listChanged" => false}
    }
  end

  @impl true
  def handle_initialize(_params, state) do
    {:ok,
     %{
       protocolVersion: "2025-06-18",
       serverInfo: %{name: "MiniZinc MCP Server", version: "1.0.0"},
       capabilities: %{tools: %{listChanged: false}, resources: %{listChanged: false}, prompts: %{listChanged: false}}
     }, state}
  end

  @impl true
  def handle_list_tools(_cursor, state) do
    tools =
      MiniZincMcp.NativeService.get_tools()
      |> Map.values()
      |> Enum.map(fn t -> %{name: t.name, description: t.description, inputSchema: t.input_schema} end)
    {:ok, tools, nil, state}
  end

  @impl true
  def handle_list_prompts(_cursor, state) do
    {:ok, [], nil, state}
  end

  @impl true
  def handle_list_resources(_cursor, state) do
    {:ok, [], nil, state}
  end

  @impl true
  def handle_call_tool(name, arguments, state) do
    case GenServer.call(MiniZincMcp.NativeService, {:execute_tool, name, arguments}, 10_000) do
      {:ok, result} ->
        {:ok, result, state}

      {:error, reason} ->
        {:error, reason, state}
    end
  end
end
