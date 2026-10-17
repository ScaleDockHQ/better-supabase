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
