import { bsb } from "@/features/api/mcp-server";

/**
 * RFC 9728 protected resource metadata for `/api/mcp`, at
 * `/.well-known/oauth-protected-resource/api/mcp`.
 */
export const { fetch: GET } = bsb;
