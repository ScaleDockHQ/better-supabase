import { mcpMetadata } from "@/features/api/mcp-metadata";

/**
 * RFC 9728 protected resource metadata for `/api/mcp`, at
 * `/.well-known/oauth-protected-resource/api/mcp`.
 */
export function GET(request: Request): Response {
  return mcpMetadata.metadata(request);
}
