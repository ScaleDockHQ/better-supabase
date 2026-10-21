import type { MCPClient } from "@ai-sdk/mcp";

import type {
  SupabaseMcpModule,
  SupabaseMcpScope,
} from "../../core/supabase-mcp.ts";

import { loadSupabaseMcp } from "../../core/supabase-mcp.ts";

/**
 * Input and output schemas by tool name, as `MCPClient.tools({ schemas })`
 * takes them.
 */
export type McpToolSchemas = Exclude<
  NonNullable<Parameters<MCPClient["toolsFromDefinitions"]>[1]>["schemas"],
  "automatic" | undefined
>;

/** Supabase's hosted MCP server. */
export const SUPABASE_MCP_URL = "https://mcp.supabase.com/mcp";

export interface SupabaseMcpOptions extends SupabaseMcpScope {
  /**
   * The server URL. Defaults to `SUPABASE_MCP_URL`; the local stack serves it
   * at `http://localhost:54321/mcp`.
   */
  readonly url?: string;
}

export interface SupabaseMcp {
  /**
   * The server URL with the scope as query parameters, for a connector server's
   * `url`.
   */
  readonly url: string;
  /**
   * For `connectTools`: types each tool's input and output, and keeps only the
   * tools the scope allows.
   */
  readonly schemas: McpToolSchemas;
}

/**
 * Supabase's MCP server for an agent: the URL to register as a connector
 * server, and the tool schemas `connectTools` types its tools with. Loads
 * `@supabase/mcp-server-supabase` for the schemas.
 */
export async function supabaseMcp(
  options: SupabaseMcpOptions = {},
  load: () => Promise<SupabaseMcpModule> = loadSupabaseMcp,
): Promise<SupabaseMcp> {
  const readOnly = options.readOnly ?? true;
  const url = new URL(options.url ?? SUPABASE_MCP_URL);

  if (options.projectRef !== undefined) {
    url.searchParams.set("project_ref", options.projectRef);
  }

  if (readOnly) {
    url.searchParams.set("read_only", "true");
  }

  if (options.features !== undefined) {
    url.searchParams.set("features", options.features.join(","));
  }

  const module = await load();

  // SAFETY: createToolSchemas returns Zod input and output schemas by tool name, the shape McpToolSchemas describes.
  const schemas = module.createToolSchemas({
    ...(options.features === undefined ? {} : { features: options.features }),
    projectScoped: options.projectRef !== undefined,
    readOnly,
  }) as McpToolSchemas;

  return { url: url.href, schemas };
}
