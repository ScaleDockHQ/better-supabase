import { bsb } from "@/features/api/mcp-server";

/**
 * The MCP endpoint (Streamable HTTP, stateless). Without a valid Bearer token
 * it answers 401 with the RFC 9728 metadata URL, so clients can sign in with
 * Supabase Auth's OAuth server.
 */
export const { fetch: GET, fetch: POST, fetch: OPTIONS, fetch: DELETE } = bsb;
