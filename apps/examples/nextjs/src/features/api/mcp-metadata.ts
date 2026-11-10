import "server-only";
import { createMcp } from "better-supabase/mcp";

import { betterSupabaseCore } from "@/lib/supabase/core";

/**
 * The discovery half of the MCP server in `mcp-server.ts`: RFC 9728 metadata
 * depends on the request URL and the Supabase project, not on the tools, so the
 * well-known route builds it over the core block set and loads none of the
 * tools' blocks.
 */
export const mcpMetadata = createMcp(betterSupabaseCore, {
  name: "example-saas",
  version: "1.0.0",
});
