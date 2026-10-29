export {
  createMcpAuth,
  MCP_AUTH_STATE_KEY,
  withBetterSupabaseMcp,
} from "./sdk.ts";

export {
  supabaseMcpHandler,
  type SupabaseMcpHandlerOptions,
  type SupabaseMcpLoaders,
} from "./supabase.ts";

export type {
  SupabaseMcpFeature,
  SupabaseMcpModule,
  SupabaseMcpPlatformModule,
  SupabaseMcpScope,
} from "../../core/supabase-mcp.ts";

export type {
  BetterMcpAuth,
  BetterMcpServer,
  BetterToolCallback,
  BetterToolConfig,
  BetterToolContext,
  BetterToolExtra,
  McpAuthOptions,
  McpFetchHandler,
  ToolRegistrar,
} from "./sdk.ts";

export type { AllowedCaller, GuardOptions } from "../../server/respond.ts";
