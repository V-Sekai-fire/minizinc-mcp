# MiniZinc MCP Server

A Model Context Protocol (MCP) server that provides MiniZinc constraint programming capabilities.

## Features

- Convert planning domains to MiniZinc format
- Convert commands, tasks, and multigoals to MiniZinc
- Solve MiniZinc models using various solvers
- List available MiniZinc solvers
- Check MiniZinc availability

## Quick Start

### Prerequisites

- Elixir 1.18+
- MiniZinc installed and available in PATH

> **Note**: MiniZinc is automatically installed in the Docker image.

### Installation

```bash
git clone <repository-url>
cd minizinc-mcp
mix deps.get
mix compile
```

## Usage

### STDIO Transport (Default)

For local development:

```bash
mix mcp.server
```

Or using release:

```bash
./_build/prod/rel/minizinc_mcp/bin/minizinc_mcp start
```

### HTTP Transport

For web deployments (e.g., Smithery):

```bash
PORT=8081 MIX_ENV=prod ./_build/prod/rel/minizinc_mcp/bin/minizinc_mcp start
```

**Endpoints:**

- `POST /` - JSON-RPC 2.0 MCP requests
- `GET /sse` - Server-Sent Events for streaming
- `GET /health` - Health check

### Docker

```bash
docker build -t minizinc-mcp .
docker run -d -p 8081:8081 --name minizinc-mcp minizinc-mcp
```

## Tools

The server provides the following MCP tools:

- `minizinc_convert_domain` - Convert a planning domain to MiniZinc
- `minizinc_convert_command` - Convert a command to MiniZinc
- `minizinc_convert_task` - Convert a task to MiniZinc
- `minizinc_convert_multigoal` - Convert a multigoal to MiniZinc
- `minizinc_solve` - Solve a MiniZinc model
- `minizinc_list_solvers` - List available solvers
- `minizinc_check_available` - Check if MiniZinc is available

### Example

**STDIO:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "minizinc_solve",
    "arguments": {
      "model_content": "var int: x; constraint x > 0; solve satisfy;",
      "solver": "chuffed"
    }
  }
}
```

**HTTP:**

```bash
curl -X POST http://localhost:8081/ \
  -H "Content-Type: application/json" \
  -H "mcp-protocol-version: 2025-06-18" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "minizinc_solve", "arguments": {"model_content": "var int: x; constraint x > 0; solve satisfy;", "solver": "chuffed"}}}'
```

## Configuration

**Environment Variables:**

- `MCP_TRANSPORT` - Transport type (`"http"` or `"stdio"`)
- `PORT` - HTTP server port (default: 8081)
- `HOST` - HTTP server host (default: `0.0.0.0` if PORT set, else `localhost`)
- `MIX_ENV` - Environment (`prod`, `dev`, `test`)
- `ELIXIR_ERL_OPTIONS` - Erlang options (set to `"+fnu"` for UTF-8)
- `MCP_SSE_ENABLED` - Enable/disable Server-Sent Events (default: `true`, set to `"false"` to disable)

**Transport Selection:**

1. If `MCP_TRANSPORT` is set, use that transport
2. If `PORT` is set, use HTTP transport
3. Otherwise, use STDIO transport (default)

## Troubleshooting

**MiniZinc not found**: Ensure MiniZinc is installed and available in PATH. For Docker, MiniZinc is included in the image.

**Port already in use**: Change `PORT` environment variable or stop conflicting services.

**Compilation errors**: Run `mix deps.get && mix clean && mix compile`.

**Debug mode**: Use `MIX_ENV=dev mix mcp.server` for verbose logging.

## Requirements

- Elixir 1.18+
- MiniZinc installed and available in PATH (or use Docker image)

## License

MIT License - see LICENSE.md for details.

