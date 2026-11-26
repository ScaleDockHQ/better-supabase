import type {
  ElicitResult,
  ElicitationRequest,
  InitializeResult,
  ListToolsResult,
  MCPClient,
  OAuthClientProvider,
} from "@ai-sdk/mcp";
import type { ToolSet } from "ai";

import {
  ElicitationRequestSchema,
  createMCPClient,
  mcpAppClientCapabilities,
  splitMCPAppTools,
} from "@ai-sdk/mcp";
import { fingerprintTools } from "ai";

import type {
  ConnectorServer,
  Connectors,
} from "../../blocks/connectors/connectors.ts";
import type { DbError } from "../../core/errors.ts";
import type { CredentialProvider } from "../../credentials/provider.ts";
import type { VaultCredentials } from "../../credentials/vault.ts";
import type { McpToolSchemas } from "./supabase.ts";

import { errorText, isRecord, sha256Hex } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { importOptionalPeer } from "../../core/optional-peer.ts";
import { AsyncResult, err, ok } from "../../core/result.ts";
import {
  credentialRefInTenant,
  foreignCredentialRef,
} from "../../credentials/provider.ts";
import { isOAuthRef, vaultOAuthProvider } from "./oauth.ts";

export interface ConnectToolsOptions {
  /** The connectors block as the user. */
  readonly connectors: Connectors;
  readonly server: ConnectorServer;
  readonly userId: string;
  /** For `oauth` servers whose grant lives in Vault. */
  readonly vault?: VaultCredentials;
  /** Resolves `header` refs and grants from other providers (Vercel Connect). */
  readonly credentials?: CredentialProvider;
  /** The OAuth callback URL, for refreshing tokens. */
  readonly redirectUrl?: string;
  /** Returns `@vercel/connect/mcp`; defaults to importing it on first use. */
  readonly loadConnectMcp?: () => Promise<unknown>;
  /** Reuses the MCP session per chat. */
  readonly chatKey?: string;
  /** Asks for MCP Apps and returns their app-only tools apart. */
  readonly apps?: boolean;
  /** Answers the server's elicitation requests; declined without one. */
  readonly elicit?: (request: ElicitationRequest) => Promise<ElicitResult>;
  /** Prefixes tool names, such as `github_`, so servers don't collide. */
  readonly prefix?: string;
  /**
   * `follow` lets the transport follow an HTTP redirect from this server. The
   * default, `error`, refuses one, so a moved server can't send the user's
   * token to another origin.
   */
  readonly redirect?: "follow" | "error";
  /**
   * `false` skips the `server/discover` probe for a server that needs
   * `initialize` as its first request. Defaults to `true`.
   */
  readonly protocolVersionDiscovery?: boolean;
  /**
   * Types the tools and keeps only the ones it names, such as
   * `supabaseMcp().schemas`. The fingerprint still covers every tool the server
   * lists.
   */
  readonly schemas?: McpToolSchemas;
  /**
   * Retries a tool call after a transient transport failure this many times
   * (the MCP client's `maxRetries`). Default 0.
   */
  readonly maxRetries?: number;
  /**
   * `true` fills `toolApproval` with every tool the server doesn't mark
   * `readOnlyHint: true`. A tool without the annotation asks. Pass it as the
   * agent's `toolApproval` (or `agentToolApproval` to merge it). The
   * annotations are the server's claim, so this only reduces prompts for a
   * server you trust.
   */
  readonly askUnlessReadOnly?: boolean;
}

/** A `toolApproval` map: the tools that wait for the user. */
export type McpToolApproval = Readonly<Record<string, "user-approval">>;

export interface ConnectedTools {
  readonly tools: ToolSet;
  /**
   * The tools that wait for the user, by prefixed name; empty unless
   * `askUnlessReadOnly`. It is the per-agent `toolApproval` the AI SDK now
   * reads, not `needsApproval` on each tool.
   */
  readonly toolApproval: McpToolApproval;
  /** Tools only an MCP App may call; empty unless `apps`. */
  readonly appTools: ToolSet;
  readonly client: MCPClient;
  readonly fingerprint: string;
  close(): Promise<void>;
}

const forbidden = (message: string, hint: string): DbError =>
  dbError("forbidden", message, { hint });

interface ConnectMcpModule {
  connectAuthProvider(
    connector: string,
    params: {
      subject: { type: "user"; id: string };
      scopes?: string[];
      installationId?: string;
    },
    options?: { redirectUrl?: string },
  ): OAuthClientProvider;
}

const isConnectMcp = (value: unknown): value is ConnectMcpModule =>
  isRecord(value) && typeof value["connectAuthProvider"] === "function";

/**
 * Loads `@vercel/connect/mcp` only for a server whose grant is a Connect
 * connector; it needs `@ai-sdk/mcp`, which this entry already imports.
 */
const getConnectMcp = (): Promise<unknown> =>
  importOptionalPeer("@vercel/connect/mcp");

/**
 * The transport's error, as a `DbError`. A Connect grant without consent throws
 * `ConsentRequiredError` with the URL the user approves it at.
 */
function transportError(cause: unknown): DbError {
  if (
    cause instanceof Error &&
    cause.name === "ConsentRequiredError" &&
    isRecord(cause) &&
    typeof cause["url"] === "string"
  ) {
    return dbError("forbidden", cause.message, {
      hint: "CONNECTOR_AUTHORIZATION_REQUIRED",
      details: cause["url"],
    });
  }

  return dbError("network", errorText(cause), {
    hint: "CONNECTOR_UNREACHABLE",
  });
}

async function authOf(
  options: ConnectToolsOptions,
): Promise<
  | {
      ok: true;
      headers: Record<string, string>;
      provider?: OAuthClientProvider;
    }
  | { ok: false; error: DbError }
> {
  const { server } = options;

  switch (server.authType) {
    case "none": {
      return { ok: true, headers: {} };
    }

    case "header": {
      if (
        server.credentialRef === undefined ||
        options.credentials === undefined
      ) {
        return {
          ok: false,
          error: forbidden(
            `${server.name} needs credentials`,
            "CONNECTOR_NOT_AUTHORIZED",
          ),
        };
      }

      if (!credentialRefInTenant(server.credentialRef, server.organizationId)) {
        return {
          ok: false,
          error: foreignCredentialRef(server.organizationId),
        };
      }

      const token = await options.credentials.getToken(server.credentialRef, {
        subject: { type: "app" },
      });

      return token.ok
        ? { ok: true, headers: { ...token.data.headers } }
        : { ok: false, error: token.error };
    }

    case "oauth": {
      const grant = server.grant;

      if (grant === undefined) {
        return {
          ok: false,
          error: forbidden(
            `Connect ${server.name} first`,
            "CONNECTOR_NOT_AUTHORIZED",
          ),
        };
      }

      if (isOAuthRef(grant.credentialRef)) {
        if (options.vault === undefined) {
          return {
            ok: false,
            error: forbidden(
              "connectTools needs vault for OAuth grants",
              "CONNECTOR_NOT_AUTHORIZED",
            ),
          };
        }

        return {
          ok: true,
          headers: {},
          provider: vaultOAuthProvider({
            vault: options.vault,
            server,
            userId: options.userId,
            redirectUrl: options.redirectUrl ?? "http://localhost/",
          }),
        };
      }

      const { connector, installationId } = grant.credentialRef;

      if (
        grant.credentialRef.provider === "vercel-connect" &&
        typeof connector === "string"
      ) {
        const module = await (options.loadConnectMcp ?? getConnectMcp)();

        if (!isConnectMcp(module)) {
          return {
            ok: false,
            error: forbidden(
              "Connect grants need the @vercel/connect package: pnpm add @vercel/connect",
              "CONNECTOR_NOT_AUTHORIZED",
            ),
          };
        }

        return {
          ok: true,
          headers: {},
          provider: module.connectAuthProvider(
            connector,
            {
              subject: { type: "user", id: options.userId },
              scopes: [...grant.scopes],
              ...(typeof installationId === "string" ? { installationId } : {}),
            },
            options.redirectUrl === undefined
              ? {}
              : { redirectUrl: options.redirectUrl },
          ),
        };
      }

      if (options.credentials === undefined) {
        return {
          ok: false,
          error: forbidden(
            `connectTools needs credentials for ${grant.credentialRef.provider}`,
            "CONNECTOR_NOT_AUTHORIZED",
          ),
        };
      }

      const token = await options.credentials.getToken(grant.credentialRef, {
        subject: { type: "user", id: options.userId },
        scopes: grant.scopes,
      });

      return token.ok
        ? { ok: true, headers: { ...token.data.headers } }
        : { ok: false, error: token.error };
    }

    default: {
      const unreachable: never = server.authType;

      return unreachable;
    }
  }
}

/** One digest over the per-tool fingerprints, in name order. */
async function digestOf(fingerprints: Record<string, string>): Promise<string> {
  const entries = Object.entries(fingerprints).toSorted(([a], [b]) =>
    a < b ? -1 : a > b ? 1 : 0,
  );

  return `sha256:${await sha256Hex(JSON.stringify(entries))}`;
}

/** The names of the tools that aren't read-only, in the `toolApproval` form. */
function approvalUnlessReadOnly(
  tools: ToolSet,
  definitions: ListToolsResult,
): Record<string, "user-approval"> {
  const readOnly = new Set(
    definitions.tools.flatMap((definition) =>
      definition.annotations?.readOnlyHint === true ? [definition.name] : [],
    ),
  );

  return Object.fromEntries(
    Object.keys(tools).flatMap((name) =>
      readOnly.has(name) ? [] : [[name, "user-approval" as const]],
    ),
  );
}

function prefixedApproval(
  approval: Record<string, "user-approval">,
  prefix: string | undefined,
): Record<string, "user-approval"> {
  if (prefix === undefined || prefix === "") {
    return approval;
  }

  return Object.fromEntries(
    Object.entries(approval).map(([name, value]) => [
      `${prefix}${name}`,
      value,
    ]),
  );
}

function prefixed(tools: ToolSet, prefix: string | undefined): ToolSet {
  if (prefix === undefined || prefix === "") {
    return tools;
  }

  return Object.fromEntries(
    Object.entries(tools).map(([name, tool]) => [`${prefix}${name}`, tool]),
  );
}

/**
 * Connects to a server as the user and returns its tools, once the fingerprint
 * of their definitions is approved. A changed tool list waits for an admin
 * (`CONNECTOR_TOOLS_CHANGED`) and the client is closed. Close the client when
 * the run ends.
 */
export function connectTools(
  options: ConnectToolsOptions,
): AsyncResult<ConnectedTools> {
  const { connectors, server } = options;

  return AsyncResult.from(async () => {
    if (!server.enabled) {
      return err(
        forbidden(`${server.name} is turned off`, "CONNECTOR_DISABLED"),
      );
    }

    const authorization = await authOf(options);

    if (!authorization.ok) {
      return err(authorization.error);
    }

    const session = await connectors.sessions.get({
      serverId: server.id,
      chatKey: options.chatKey,
    });

    const previous = session.ok ? session.data : undefined;
    const chatKey = options.chatKey ?? "";
    let sessionId = previous?.sessionId;
    let client: MCPClient;

    try {
      client = await createMCPClient({
        transport: {
          type: server.transport,
          url: server.url,
          headers: authorization.headers,
          ...(authorization.provider === undefined
            ? {}
            : { authProvider: authorization.provider }),
          ...(previous?.sessionId === undefined
            ? {}
            : { initialSessionId: previous.sessionId }),
          ...(options.redirect === undefined
            ? {}
            : { redirect: options.redirect }),
          onSessionIdChange: (next) => {
            sessionId = next;

            if (next === undefined) {
              void connectors.sessions.forget({ serverId: server.id, chatKey });
            }
          },
        },
        ...(previous?.initializeResult === undefined ||
        previous.sessionId === undefined
          ? {}
          : {
              // SAFETY: the stored value is the server's initialize result.
              initialInitializeResult:
                previous.initializeResult as InitializeResult,
            }),
        ...(options.maxRetries === undefined
          ? {}
          : { maxRetries: options.maxRetries }),
        ...(options.protocolVersionDiscovery === undefined
          ? {}
          : { protocolVersionDiscovery: options.protocolVersionDiscovery }),
        capabilities: {
          ...(options.apps === true ? mcpAppClientCapabilities : {}),
          elicitation: {},
        },
      });
    } catch (cause) {
      return err(transportError(cause));
    }

    const close = (): Promise<void> => client.close().catch(() => {});

    try {
      client.onElicitationRequest(ElicitationRequestSchema, (request) =>
        options.elicit === undefined
          ? { action: "decline" }
          : options.elicit(request),
      );

      if (sessionId !== undefined) {
        void connectors.sessions.upsert({
          serverId: server.id,
          session: {
            chatKey,
            sessionId,
            initializeResult: { ...client.initializeResult },
          },
        });
      }

      const definitions: ListToolsResult = await client.listTools();

      const split =
        options.apps === true
          ? splitMCPAppTools(definitions)
          : { modelVisible: definitions, appVisible: { tools: [] } };

      const listed = client.toolsFromDefinitions(split.modelVisible);

      const modelTools =
        options.schemas === undefined
          ? listed
          : client.toolsFromDefinitions(split.modelVisible, {
              schemas: options.schemas,
            });

      const toolApproval =
        options.askUnlessReadOnly === true
          ? approvalUnlessReadOnly(modelTools, split.modelVisible)
          : {};

      const fingerprints = await fingerprintTools(listed);
      const fingerprint = await digestOf(fingerprints);

      const status = await connectors.fingerprints.check({
        serverId: server.id,
        fingerprint,
        tools: fingerprints,
      });

      if (!status.ok) {
        await close();

        return status;
      }

      if (status.data !== "approved") {
        await close();

        return err(
          forbidden(
            `The tools of ${server.name} changed and wait for an admin's approval`,
            "CONNECTOR_TOOLS_CHANGED",
          ),
        );
      }

      return ok({
        tools: prefixed(modelTools, options.prefix),
        toolApproval: prefixedApproval(toolApproval, options.prefix),
        appTools: prefixed(
          client.toolsFromDefinitions(split.appVisible),
          options.prefix,
        ),
        client,
        fingerprint,
        close,
      });
    } catch (cause) {
      await close();

      return err(transportError(cause));
    }
  });
}

export interface ConnectAllOptions extends Omit<
  ConnectToolsOptions,
  "server" | "prefix"
> {
  /**
   * The transport options for one server, such as `{ redirect: "follow" }` for
   * a server that moved or `{ protocolVersionDiscovery: false }` for one that
   * needs `initialize` first. They win over the shared ones.
   */
  readonly serverOptions?: (
    server: ConnectorServer,
  ) => Pick<ConnectToolsOptions, "redirect" | "protocolVersionDiscovery">;
}

export interface ConnectAllResult {
  readonly tools: ToolSet;
  /** The merged `toolApproval` of the servers; see `ConnectedTools`. */
  readonly toolApproval: McpToolApproval;
  /** The servers left out, with why. */
  readonly skipped: readonly {
    readonly server: ConnectorServer;
    readonly error: DbError;
  }[];
  close(): Promise<void>;
}

/**
 * Connects to several servers (an agent's `connectorIds`) and merges their
 * tools, each prefixed with its server's name. A server that fails is skipped
 * and reported, not fatal.
 */
export async function connectAll(
  servers: readonly ConnectorServer[],
  options: ConnectAllOptions,
): Promise<ConnectAllResult> {
  const { serverOptions, ...shared } = options;

  const results = await Promise.all(
    servers.map(async (server) => ({
      server,
      result: await connectTools({
        ...shared,
        ...serverOptions?.(server),
        server,
        prefix: `${server.name.toLowerCase().replaceAll(/[^a-z0-9]+/g, "_")}_`,
      }),
    })),
  );

  const tools: ToolSet = {};
  const toolApproval: Record<string, "user-approval"> = {};
  const skipped: { server: ConnectorServer; error: DbError }[] = [];
  const open: ConnectedTools[] = [];

  for (const { server, result } of results) {
    if (result.ok) {
      Object.assign(tools, result.data.tools);
      Object.assign(toolApproval, result.data.toolApproval);
      open.push(result.data);
    } else {
      skipped.push({ server, error: result.error });
    }
  }

  return {
    tools,
    toolApproval,
    skipped,
    close: async () => {
      await Promise.all(open.map((connected) => connected.close()));
    },
  };
}
