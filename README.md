# MiniZinc MCP Server

[![smithery badge](https://smithery.ai/badge/@V-Sekai-fire/minizinc-mcp)](https://smithery.ai/server/@V-Sekai-fire/minizinc-mcp)

A Model Context Protocol (MCP) server that provides MiniZinc constraint programming capabilities.

## Features

- Solve MiniZinc models using chuffed solver
- Support for both MZN (model) and DZN (data) content as strings
- Output format: Parses DZN format for variable extraction, passthroughs output_text from explicit output statements

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

- `minizinc_solve` - Solve a MiniZinc model (chuffed solver only)

### Standard Library Support

The `minizinc_solve` tool automatically includes common MiniZinc standard libraries (e.g., `alldifferent.mzn`) 
if they are not already present in the model. This means you can use standard functions like `all_different` 
without needing to add explicit `include` statements.

### Output Format

The `minizinc_solve` tool returns solutions in the following format:

- **DZN format parsing**: When MiniZinc provides DZN format output (models without explicit `output` statements), variables are parsed and returned as structured data (e.g., `{"x": 10, "y": [1, 2, 3]}`)
- **Output text passthrough**: When models include explicit `output` statements, the output text is passthrough'd in the `output_text` field (e.g., `{"output_text": "x = 10\n"}`)
- **Both formats**: When both DZN and explicit output are available, both are included in the response

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
      "model_content": "var int: x; constraint x > 0; solve satisfy;"
    }
  }
}
```

**HTTP:**

```bash
curl -X POST http://localhost:8081/ \
  -H "Content-Type: application/json" \
  -H "mcp-protocol-version: 2025-06-18" \
  -d '{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "minizinc_solve", "arguments": {"model_content": "var int: x; constraint x > 0; solve satisfy;"}}}'
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