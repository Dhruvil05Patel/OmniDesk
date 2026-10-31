# Model Context Protocol (MCP) Swift Specification Reference

## Official Documentation Sources
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)
- [Anthropic: MCP GitHub Repository](https://github.com/modelcontextprotocol)
- [JSON-RPC 2.0 Specification](https://www.jsonrpc.org/specification)

---

## 1. Standard JSON-RPC 2.0 Error Codes

| Code | Message | Description |
| :--- | :--- | :--- |
| **-32700** | Parse error | Invalid JSON received by the server. |
| **-32600** | Invalid Request | The JSON sent is not a valid Request object. |
| **-32601** | Method not found | The method does not exist / is not recognized. |
| **-32602** | Invalid params | Invalid method parameter(s). |
| **-32603** | Internal error | Internal JSON-RPC error. |
| **-32000** | Tool execution error | Domain-specific tool failure. |
| **-32001** | User rejected | Action cancelled by user confirmation policy. |

---

## 2. MCP Content Payload Format
When `tools/call` succeeds, MCP expects a structured `content` array:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Event 'Team Sync' scheduled successfully."
      }
    ],
    "isError": false
  }
}
```

If an error occurred within the tool, `isError: true` should be set with diagnostic text in the content block.

---

## 3. Stdio Transport in Swift
When exposing an MCP server over standard input/output (`stdio`):
- Read input lines continuously from `readLine()`.
- Flush standard output immediately after writing: `fflush(stdout)`.
- Direct all internal diagnostics and debug logs to `FileHandle.standardError` (`stderr`) to avoid corrupting the JSON-RPC stream on `stdout`.
