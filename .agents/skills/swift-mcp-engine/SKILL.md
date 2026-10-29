---
name: swift-mcp-engine
description: Implements, debugs, and integrates the Model Context Protocol (MCP) in Swift over JSON-RPC 2.0. Use when building native Swift MCP servers or clients, mapping Swift tools to JSON Schema, or handling tools/list and tools/call requests.
---

# Swift MCP Engine Skill

Provides production-ready patterns for building native, lightweight Model Context Protocol (MCP) clients and servers in Swift over JSON-RPC 2.0.

## 1. When to Use This Skill
- Implementing an MCP server in Swift to expose native macOS tools to external AI clients (Claude Desktop, Cursor).
- Connecting a Swift application to external community MCP servers via stdio or local HTTP/SSE.
- Translating Swift typed structs and protocols into valid MCP `inputSchema` specifications.
- Routing `tools/list` and `tools/call` JSON-RPC messages.

## 2. JSON-RPC 2.0 Protocol Skeleton

```swift
public struct JSONRPCRequest: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: AnyCodableValue?
    public let method: String
    public let params: [String: AnyCodableValue]?
}

public struct JSONRPCResponse: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: AnyCodableValue?
    public let result: AnyCodableValue?
    public let error: JSONRPCError?
}
```

## 3. Core MCP Method Handlers

### `initialize`
Returns server capabilities and schema compliance:
```swift
func handleInitialize(id: AnyCodableValue?) -> JSONRPCResponse {
    return .success(id: id, result: .dictionary([
        "protocolVersion": .string("2024-11-05"),
        "capabilities": .dictionary(["tools": .dictionary([:])]),
        "serverInfo": .dictionary(["name": .string("omnidesk-native"), "version": .string("1.0.0")])
    ]))
}
```

### `tools/list`
Aggregates all registered tools across active connectors:
```swift
func handleToolsList(id: AnyCodableValue?, tools: [ToolDefinition]) -> JSONRPCResponse {
    let toolList = tools.map { tool -> AnyCodableValue in
        .dictionary([
            "name": .string(tool.name),
            "description": .string(tool.description),
            "inputSchema": .dictionary([
                "type": .string("object"),
                "properties": ...
            ])
        ])
    }
    return .success(id: id, result: .dictionary(["tools": .array(toolList)]))
}
```

### `tools/call`
Executes tool action through Safety Policy Gate and formats return content:
```swift
func handleToolsCall(id: AnyCodableValue?, name: String, arguments: [String: Any]) async -> JSONRPCResponse {
    // 1. Evaluate safety policy (prompt user if destructive)
    // 2. Dispatch to connector
    // 3. Wrap response in MCP Content format:
    let content: [AnyCodableValue] = [.dictionary(["type": .string("text"), "text": .string(output)])]
    return .success(id: id, result: .dictionary(["content": .array(content), "isError": .bool(false)]))
}
```

For complete protocol definitions, error codes, and transport patterns, see [MCP Specification Reference](references/mcp-spec-reference.md).
