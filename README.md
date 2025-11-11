# MiniZinc MCP Server

A Model Context Protocol (MCP) server that provides MiniZinc constraint programming capabilities.

## Features

- Solve MiniZinc models using chuffed solver (fixed, not configurable)
- Support for both MZN (model) and DZN (data) content as strings
- Automatic standard library inclusion (e.g., `alldifferent.mzn`) when not present in models
- Comprehensive output format: Parses DZN format for variable extraction, passthroughs output_text from explicit output statements
- JSON-RPC 2.0 protocol support via STDIO or HTTP transports
- Server-Sent Events (SSE) support for streaming responses

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

### `minizinc_solve`

Solve a MiniZinc model using the chuffed solver (fixed, not configurable).

#### Parameters

- `model_content` (string, required): MiniZinc model content (.mzn) as string
- `data_content` (string, optional): DZN data content as string (e.g., `"n = 8;"`). Must be valid DZN format. Parsed and included in response as `input_data` field.
- `timeout` (integer, optional): Optional timeout in milliseconds (default: no timeout, runs indefinitely)
- `auto_include_stdlib` (boolean, optional): Automatically include standard MiniZinc libraries (e.g., `alldifferent.mzn`) if not present (default: `true`)

#### Standard Library Support

The `minizinc_solve` tool automatically includes common MiniZinc standard libraries (e.g., `alldifferent.mzn`) 
if they are not already present in the model (when `auto_include_stdlib` is `true`). This means you can use 
standard functions like `all_different` without needing to add explicit `include` statements.

#### Output Format

The `minizinc_solve` tool returns solutions as JSON in the following format:

- **DZN format parsing**: When MiniZinc provides DZN format output (models without explicit `output` statements), variables are parsed and returned as structured data (e.g., `{"x": 10, "y": [1, 2, 3]}`)
- **Output text passthrough**: When models include explicit `output` statements, the output text is passthrough'd in the `output_text` field (e.g., `{"output_text": "x = 10\n"}`)
- **Both formats**: When both DZN and explicit output are available, both are included in the response
- **Input data**: When `data_content` is provided, the parsed DZN data is included in the `input_data` field
- **Status**: Solution status (e.g., `"SATISFIED"`, `"OPTIMAL_SOLUTION"`, `"UNSATISFIABLE"`) is included when available

The response is always returned as a JSON string in the MCP content field.

### Examples

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

**With data content:**

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "minizinc_solve",
    "arguments": {
      "model_content": "var int: n; array[1..n] of var int: x; constraint all_different(x); solve satisfy;",
      "data_content": "n = 8;",
      "timeout": 30000
    }
  }
}
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

## Version

Current version: **1.0.0-dev1** (see `mix.exs` for latest version)

## Requirements

- Elixir 1.18+
- Erlang/OTP 26+
- MiniZinc 2.9.3+ installed and available in PATH (or use Docker image which includes MiniZinc)

## Development

### Building

```bash
mix deps.get
mix compile
```

### Testing

```bash
mix test
```

### Building Release

```bash
MIX_ENV=prod mix release
```

### Running Locally

For STDIO transport (default):
```bash
mix mcp.server
```

For HTTP transport:
```bash
MCP_TRANSPORT=http PORT=8081 mix run --no-halt
```

## License

MIT License - see LICENSE.md for details.

## Copyright

Copyright (c) 2025-present K. S. Ernest (iFire) Lee

