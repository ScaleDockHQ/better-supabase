/**
 * The transport-free part of MCP: protocol versions, tool and result shapes,
 * the handshake results and a dispatcher for one JSON-RPC message. The
 * Streamable HTTP server in `mcp.ts` and the CLI's stdio server share it, so
 * it imports nothing from Node.
 */

import { jsonReplacer } from "../core/json.ts";
import { SPEC_PINS } from "../core/spec-pins.ts";
import {
  INVALID_PARAMS,
  INVALID_REQUEST,
  isObject,
  isRpcRequest,
  type Json,
  type JsonRpcRequest,
  META_SERVER_INFO,
  META_VERSION,
  METHOD_NOT_FOUND,
  PARSE_ERROR,
  rpcErrorBody,
} from "./json-rpc.ts";

export const MCP_PROTOCOL_VERSION: string = SPEC_PINS.mcp;

/** Revisions before 2026-07-28 open with an `initialize` handshake. */
export const LEGACY_VERSIONS: readonly string[] = [
  "2025-11-25",
  "2025-06-18",
  "2025-03-26",
];

export const SUPPORTED_VERSIONS: readonly string[] = [
  MCP_PROTOCOL_VERSION,
  ...LEGACY_VERSIONS,
];

/** How long clients may cache `tools/list` and `server/discover`. */
export const LIST_TTL_MS = 300_000;

/** MCP tool annotations (hints for clients, not guarantees). */
export interface ToolAnnotations {
  readonly title?: string;
  readonly readOnlyHint?: boolean;
  readonly destructiveHint?: boolean;
  readonly idempotentHint?: boolean;
  readonly openWorldHint?: boolean;
}

/** A tool as listed by `tools/list`. */
export interface ToolInfo {
  readonly name: string;
  readonly title?: string;
  readonly description?: string;
  readonly inputSchema: Json;
  readonly outputSchema?: Json;
  readonly annotations?: ToolAnnotations;
}

export interface ToolResult {
  readonly content: readonly { readonly type: "text"; readonly text: string }[];
  readonly structuredContent?: Json;
  readonly isError?: boolean;
}

/** What a server tells clients about itself. */
export interface ServerDescription {
  readonly info: {
    readonly name: string;
    readonly version: string;
    readonly title?: string;
  };
  readonly instructions?: string;
}

export const CAPABILITIES: Json = { tools: { listChanged: false } };

/** A tool result: the value as text, and as `structuredContent` when it is an object. */
export function textResult(value: unknown, isError = false): ToolResult {
  const structured = isObject(value) ? value : undefined;

  return {
    content: [
      {
        type: "text",
        text:
          typeof value === "string"
            ? value
            : JSON.stringify(value ?? null, jsonReplacer),
      },
    ],
    ...(structured ? { structuredContent: structured } : {}),
    ...(isError ? { isError: true } : {}),
  };
}

/** A message on 2026-07-28 or later, which carries its version in `_meta`. */
export function isModernMessage(message: JsonRpcRequest): boolean {
  const meta = message.params?.["_meta"];

  return isObject(meta) && meta[META_VERSION] !== undefined;
}

/** The `initialize` result for a pre-2026-07-28 client. */
export function initializeResult(
  requested: unknown,
  server: ServerDescription,
): Json {
  return {
    protocolVersion:
      typeof requested === "string" && LEGACY_VERSIONS.includes(requested)
        ? requested
        : LEGACY_VERSIONS[0],
    capabilities: CAPABILITIES,
    serverInfo: server.info,
    ...(server.instructions ? { instructions: server.instructions } : {}),
  };
}

/** The `server/discover` result for a 2026-07-28 client. */
export function discoverResult(server: ServerDescription): Json {
  return {
    supportedVersions: [...SUPPORTED_VERSIONS],
    capabilities: CAPABILITIES,
    ...(server.instructions ? { instructions: server.instructions } : {}),
    ttlMs: LIST_TTL_MS,
    cacheScope: "private",
  };
}

/** A result as a 2026-07-28 response marks it: complete, with the server's info. */
export function modernResult(result: object, server: ServerDescription): Json {
  return {
    ...result,
    resultType: "complete",
    _meta: { [META_SERVER_INFO]: server.info },
  };
}

/** A server that one transport-free dispatcher can answer for. */
export interface ProtocolServer extends ServerDescription {
  listTools(): Promise<readonly ToolInfo[]>;
  /** The tool's result, or `undefined` when no tool has the name. */
  callTool(name: string, args: unknown): Promise<ToolResult | undefined>;
}

const response = (id: JsonRpcRequest["id"], result: Json): Json => ({
  jsonrpc: "2.0",
  id: id ?? null,
  result,
});

/**
 * The JSON-RPC response to one message, or `undefined` for a notification.
 * It answers `initialize`, `server/discover`, `ping`, `tools/list` and
 * `tools/call`, for message-based transports such as stdio.
 */
export async function answerMessage(
  message: unknown,
  server: ProtocolServer,
): Promise<Json | undefined> {
  if (!isRpcRequest(message)) {
    return rpcErrorBody(
      null,
      INVALID_REQUEST,
      "Expected a JSON-RPC 2.0 message",
    );
  }

  if (message.id === undefined) {
    return undefined;
  }

  const modern = isModernMessage(message);

  const reply = (result: object): Json =>
    response(message.id, modern ? modernResult(result, server) : { ...result });

  switch (message.method) {
    case "initialize": {
      return modern
        ? rpcErrorBody(
            message.id,
            METHOD_NOT_FOUND,
            "Method not found: initialize",
          )
        : reply(initializeResult(message.params?.["protocolVersion"], server));
    }

    case "server/discover": {
      return reply(discoverResult(server));
    }

    case "ping": {
      return reply({});
    }

    case "tools/list": {
      return reply({
        tools: await server.listTools(),
        ...(modern ? { ttlMs: LIST_TTL_MS, cacheScope: "private" } : {}),
      });
    }

    case "tools/call": {
      const name = message.params?.["name"];

      const result =
        typeof name === "string"
          ? await server.callTool(name, message.params?.["arguments"])
          : undefined;

      return result === undefined
        ? rpcErrorBody(
            message.id,
            INVALID_PARAMS,
            `Unknown tool ${JSON.stringify(name)}`,
          )
        : reply(result);
    }

    default: {
      return rpcErrorBody(
        message.id,
        METHOD_NOT_FOUND,
        `Method not found: ${message.method}`,
      );
    }
  }
}

/** The response to one line of a newline-delimited JSON-RPC stream. */
export function answerLine(
  line: string,
  server: ProtocolServer,
): Promise<Json | undefined> {
  let message: unknown;

  try {
    message = JSON.parse(line);
  } catch {
    return Promise.resolve(rpcErrorBody(null, PARSE_ERROR, "Parse error"));
  }

  return answerMessage(message, server);
}
