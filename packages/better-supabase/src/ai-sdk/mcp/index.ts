export {
  authorizeConnector,
  type AuthorizeConnectorOptions,
  completeConnector,
  mcpOAuthRef,
  vaultOAuthProvider,
  type VaultOAuthProvider,
  type VaultOAuthProviderOptions,
} from "./oauth.ts";

export {
  connectAll,
  type ConnectAllOptions,
  type ConnectAllResult,
  type ConnectedTools,
  connectTools,
  type ConnectToolsOptions,
} from "./mcp.ts";

export {
  type McpToolSchemas,
  SUPABASE_MCP_URL,
  supabaseMcp,
  type SupabaseMcp,
  type SupabaseMcpOptions,
} from "./supabase.ts";

export type {
  SupabaseMcpFeature,
  SupabaseMcpScope,
} from "../../core/supabase-mcp.ts";

export {
  type DedupeMcpEventsOptions,
  dedupeMcpEvents,
  type McpEventRouteOptions,
  mcpEventRoute,
  postgresMcpEventStore,
  type PostgresMcpEventStoreOptions,
} from "./events.ts";

export {
  type McpPromptSummary,
  type McpResourceClient,
  type McpResourceToolsOptions,
  mcpPrompts,
  mcpPromptMessages,
  mcpResourceTools,
} from "./resources.ts";
