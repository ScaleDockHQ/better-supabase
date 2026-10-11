import { importOptionalPeer } from "./optional-peer.ts";
/** The feature groups Supabase's MCP server turns on with `features`. */
export type SupabaseMcpFeature =
  | "account"
  | "branching"
  | "database"
  | "debugging"
  | "development"
  | "docs"
  | "functions"
  | "storage";

/** Which project and tools a Supabase MCP server exposes. */
export interface SupabaseMcpScope {
  /**
   * Scopes the server to one project. Without it the tools reach every
   * project the Management API token can.
   */
  readonly projectRef?: string;
  /** Runs SQL read-only and leaves out the tools that write. Defaults to true. */
  readonly readOnly?: boolean;
  /** The feature groups to turn on; the server's defaults when unset. */
  readonly features?: readonly SupabaseMcpFeature[];
}

/** The parts of `@supabase/mcp-server-supabase` better-supabase calls. */
export interface SupabaseMcpModule {
  createToolSchemas(options: {
    features?: readonly SupabaseMcpFeature[];
    projectScoped?: boolean;
    readOnly?: boolean;
  }): Record<string, unknown>;
  createSupabaseMcpHandler(options: {
    platform: unknown;
    projectId?: string;
    readOnly?: boolean;
    features?: string[];
  }): {
    fetch(
      request: Request,
      options?: { readonly authInfo?: unknown },
    ): Promise<Response>;
    close(): Promise<void>;
  };
}

/** The part of `@supabase/mcp-server-supabase/platform/api` better-supabase calls. */
export interface SupabaseMcpPlatformModule {
  createSupabaseApiPlatform(options: {
    accessToken: string;
    apiUrl?: string;
  }): unknown;
}

const INSTALL =
  "Supabase's MCP server needs @supabase/mcp-server-supabase: pnpm add @supabase/mcp-server-supabase";

export const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

function isServerModule(value: unknown): value is SupabaseMcpModule {
  return (
    isRecord(value) &&
    "createToolSchemas" in value &&
    "createSupabaseMcpHandler" in value &&
    typeof value["createToolSchemas"] === "function" &&
    typeof value["createSupabaseMcpHandler"] === "function"
  );
}

function isPlatformModule(value: unknown): value is SupabaseMcpPlatformModule {
  return (
    isRecord(value) &&
    "createSupabaseApiPlatform" in value &&
    typeof value["createSupabaseApiPlatform"] === "function"
  );
}

/**
 * Loads `@supabase/mcp-server-supabase` on first use. The specifiers are
 * variables so bundlers leave the optional peer out of apps that don't call
 * Supabase's MCP server; a missing install throws how to add it.
 */
export async function loadSupabaseMcp(): Promise<SupabaseMcpModule> {
  const loaded = await importOptionalPeer("@supabase/mcp-server-supabase");
  if (!isServerModule(loaded)) throw new TypeError(INSTALL);
  return loaded;
}

/** Loads the Management API platform of `@supabase/mcp-server-supabase`. */
export async function loadSupabaseMcpPlatform(): Promise<SupabaseMcpPlatformModule> {
  const loaded = await importOptionalPeer(
    "@supabase/mcp-server-supabase/platform/api",
  );
  if (!isPlatformModule(loaded)) throw new TypeError(INSTALL);
  return loaded;
}
