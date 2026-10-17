import { base64ToText } from "../core/base64.ts";

/** A JSON object. */
export type Json = Readonly<Record<string, unknown>>;

/** A JSON-RPC 2.0 request or notification. */
export interface JsonRpcRequest {
  readonly jsonrpc: "2.0";
  readonly id?: string | number | null;
  readonly method: string;
  readonly params?: Json;
}

export const PARSE_ERROR = -32_700;
export const INVALID_REQUEST = -32_600;
export const METHOD_NOT_FOUND = -32_601;
export const INVALID_PARAMS = -32_602;
export const HEADER_MISMATCH = -32_020;
export const UNSUPPORTED_PROTOCOL_VERSION = -32_022;

export const META_VERSION = "io.modelcontextprotocol/protocolVersion";
export const META_CAPABILITIES = "io.modelcontextprotocol/clientCapabilities";
export const META_SERVER_INFO = "io.modelcontextprotocol/serverInfo";

/** A JSON-RPC error response. */
export function rpcError(
  id: JsonRpcRequest["id"],
  code: number,
  message: string,
  status = 200,
  data?: Json,
): Response {
  return Response.json(
    {
      jsonrpc: "2.0",
      id: id ?? null,
      error: { code, message, ...(data ? { data } : {}) },
    },
    { status },
  );
}

/** A non-array object. */
export const isObject = (value: unknown): value is Json =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** An `Mcp-Name` value, decoding the `=?base64?...?=` sentinel. */
export function headerName(value: string): string {
  const encoded = /^=\?base64\?(.*)\?=$/.exec(value)?.[1];
  if (encoded === undefined) {
    return value;
  }
  try {
    return base64ToText(encoded);
  } catch {
    return value;
  }
}

/** A value as a quoted string, with backslashes and quotes escaped. */
export const quoted = (value: string): string =>
  `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;

/** A well-formed JSON-RPC 2.0 request. */
export function isRpcRequest(value: unknown): value is JsonRpcRequest {
  return (
    isObject(value) &&
    value["jsonrpc"] === "2.0" &&
    typeof value["method"] === "string" &&
    (value["params"] === undefined || isObject(value["params"]))
  );
}
