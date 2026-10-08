import type { AuthState, ResolveAuthOptions } from "../auth/resolve.ts";
import type { AiChat } from "../blocks/ai-chat/ai-chat.ts";
import type { Inbox } from "../blocks/inbox/inbox.ts";
import type {
  Knowledge,
  KnowledgeSearchOptions,
} from "../blocks/knowledge/knowledge.ts";
import type { Memory, MemoryNamespace } from "../blocks/memory/memory.ts";
import type {
  CredentialProvider,
  CredentialRef,
  CredentialSubject,
} from "../credentials/provider.ts";

import { resolveAuth } from "../auth/resolve.ts";
import { isAnonymousUser } from "../auth/view.ts";
import { isRecord } from "../blocks/shared.ts";
import { claimAt, tenantClaimPaths } from "../core/claims.ts";
import { type DbError, DbException } from "../core/errors.ts";

/**
 * eve's `SessionAuthContext`, typed structurally so this entry never imports
 * eve. `attributes` carries `tenantId`, `roles` and `isAnonymous`.
 */
export interface EveSessionAuth {
  readonly authenticator: string;
  readonly principalType: string;
  readonly principalId: string;
  readonly issuer?: string;
  readonly subject?: string;
  readonly attributes: Readonly<Record<string, string | readonly string[]>>;
}

/** The session part of the context eve passes to hooks, memory and connections. */
export interface EveSessionContext {
  readonly session: {
    readonly id: string;
    readonly auth: {
      readonly current: EveSessionAuth | null;
      readonly initiator?: EveSessionAuth | null;
    };
  };
}

// ---------------------------------------------------------------------------
// Route auth

/** Thrown by `supabaseAuth` so eve answers with `response` instead of downgrading to anonymous. */
export class EveAuthRejection extends Error {
  override readonly name = "EveAuthRejection";
  readonly response: Response;

  constructor(message: string, status = 401) {
    super(message);
    this.response = new Response(JSON.stringify({ error: message }), {
      status,
      headers: { "content-type": "application/json" },
    });
  }
}

export interface SupabaseAuthOptions extends Omit<
  ResolveAuthOptions,
  "refresh" | "leeway" | "refreshTimeoutMs"
> {
  /** The tenant claim, `config.claims.tenant`. Defaults to `tenant_id`. */
  readonly tenantClaim?: string;
  /** Extra attributes from the verified claims, merged over the defaults. */
  readonly attributes?: (
    claims: Readonly<Record<string, unknown>>,
  ) => Readonly<Record<string, string | readonly string[]>>;
}

function rolesIn(
  claims: Readonly<Record<string, unknown>>,
  tenantId: string | undefined,
): readonly string[] {
  const memberships = claims["memberships"];
  const strings = (value: unknown): string[] =>
    Array.isArray(value)
      ? value.filter((role): role is string => typeof role === "string")
      : [];
  if (tenantId === undefined) return [];
  if (Array.isArray(memberships)) {
    return [
      ...new Set(
        memberships.flatMap((entry) =>
          isRecord(entry) && entry["id"] === tenantId
            ? strings(entry["roles"])
            : [],
        ),
      ),
    ];
  }
  return isRecord(memberships) ? strings(memberships[tenantId]) : [];
}

/** The eve principal for a verified Supabase user, or `null` for anyone else. */
export function principalOf(
  auth: AuthState,
  options: Pick<SupabaseAuthOptions, "tenantClaim" | "attributes"> = {},
): EveSessionAuth | null {
  if (auth.kind !== "user") return null;
  const claims: Readonly<Record<string, unknown>> = auth.claims;
  let tenantId: string | undefined;
  for (const path of tenantClaimPaths(options.tenantClaim)) {
    tenantId ??= claimAt(claims, path);
  }
  const issuer = typeof claims["iss"] === "string" ? claims["iss"] : undefined;
  return {
    authenticator: "supabase",
    principalType: "user",
    principalId: auth.claims.sub,
    subject: auth.claims.sub,
    ...(issuer === undefined ? {} : { issuer }),
    attributes: {
      ...(tenantId === undefined ? {} : { tenantId }),
      roles: rolesIn(claims, tenantId),
      isAnonymous: isAnonymousUser(claims) ? "true" : "false",
      ...options.attributes?.(claims),
    },
  };
}

/**
 * An eve route `AuthFn` that verifies the Supabase session locally (cookie or
 * bearer) and maps the user to a principal. Requests without a session fall
 * through to the next entry; an invalid token is rejected with 401.
 */
export function supabaseAuth(
  options: SupabaseAuthOptions,
): (request: Request) => Promise<EveSessionAuth | null> {
  return async (request) => {
    const { auth } = await resolveAuth(request, options);
    if (auth.kind === "invalid")
      throw new EveAuthRejection("The Supabase session is not valid");
    return principalOf(auth, options);
  };
}

// ---------------------------------------------------------------------------
// Connections

/** eve's `ConnectionAuthorizationRequiredError`, matched by name. */
export class ConnectionAuthorizationRequiredError extends Error {
  override readonly name = "ConnectionAuthorizationRequiredError";
  readonly connectionName: string;

  constructor(
    connectionName: string,
    options: { readonly message?: string } = {},
  ) {
    super(
      options.message ?? `Connection "${connectionName}" needs authorization`,
    );
    this.connectionName = connectionName;
  }
}

/** eve's `ConnectionAuthorizationFailedError`, matched by name. */
export class ConnectionAuthorizationFailedError extends Error {
  override readonly name = "ConnectionAuthorizationFailedError";
  readonly connectionName: string;
  readonly reason: string;
  readonly retryable: boolean;

  constructor(
    connectionName: string,
    options: {
      readonly message?: string;
      readonly reason: string;
      readonly retryable: boolean;
    },
  ) {
    super(
      options.message ??
        `Connection "${connectionName}" failed: ${options.reason}`,
    );
    this.connectionName = connectionName;
    this.reason = options.reason;
    this.retryable = options.retryable;
  }
}

/** The identity eve resolves for a connection callback. */
export type EveConnectionPrincipal =
  | { readonly type: "app" }
  | {
      readonly type: "user";
      readonly id: string;
      readonly issuer?: string;
      readonly attributes?: Readonly<
        Record<string, string | readonly string[]>
      >;
    };

export interface EveConnectionRequest {
  readonly principal: EveConnectionPrincipal;
  readonly connection: { readonly url: string };
}

export interface EveTokenResult {
  readonly token: string;
  /** Epoch milliseconds. */
  readonly expiresAt?: number;
  readonly providerSubject?: string;
}

export interface EveAuthorizationChallenge {
  readonly challenge: {
    readonly url?: string;
    readonly displayName?: string;
    readonly instructions?: string;
  };
  readonly resume?: Readonly<Record<string, string>>;
}

/** A connection `auth` value for eve's `defineMcpClientConnection`. */
export interface EveConnectionAuthorization {
  /** Set on the non-interactive form. */
  readonly credentialOwner?: "app" | "user";
  /** Set on the interactive form, which eve allows only for users. */
  readonly principalType?: "user";
  readonly displayName?: string;
  getToken(request: EveConnectionRequest): Promise<EveTokenResult>;
  startAuthorization?(
    request: EveConnectionRequest & { readonly callbackUrl: string },
  ): Promise<EveAuthorizationChallenge>;
  completeAuthorization?(
    request: EveConnectionRequest & {
      readonly callbackUrl: string;
      readonly resume?: Readonly<Record<string, string>>;
      readonly callback: {
        readonly params: Readonly<Record<string, string>>;
        readonly method?: string;
      };
    },
  ): Promise<EveTokenResult>;
}

export interface CredentialAuthOptions {
  readonly provider: CredentialProvider;
  readonly ref: CredentialRef;
  /** `app` uses the app's credential; `user` the principal's own. */
  readonly owner: "app" | "user";
  /** The connection's name in errors. Defaults to the ref's provider. */
  readonly connection?: string;
  readonly scopes?: readonly string[];
  /** For `user`: let eve send the user to connect the account when the provider can. Defaults to true. */
  readonly interactive?: boolean;
}

const AUTHORIZATION_HINTS = new Set([
  "CREDENTIAL_AUTHORIZATION_REQUIRED",
  "CREDENTIAL_NOT_FOUND",
  "CREDENTIAL_SUBJECT_REQUIRED",
]);

function connectionError(name: string, error: DbError): Error {
  const hint = "hint" in error ? error.hint : undefined;
  if (
    error.kind === "not_found" ||
    (typeof hint === "string" && AUTHORIZATION_HINTS.has(hint))
  )
    return new ConnectionAuthorizationRequiredError(name, {
      message: error.message,
    });
  if (error.kind === "forbidden" || error.kind === "invalid_input")
    return new ConnectionAuthorizationFailedError(name, {
      message: error.message,
      reason: typeof hint === "string" ? hint : error.kind,
      retryable: false,
    });
  return new DbException(error);
}

/**
 * An eve connection `authorization` over a better-supabase
 * `CredentialProvider` (Vault, Vercel Connect or your own): tokens come from
 * the provider for the app or for the session's user. A user without a stored
 * credential gets eve's authorization flow when the provider supports one.
 */
export function credentialAuth(
  options: CredentialAuthOptions,
): EveConnectionAuthorization {
  const name = options.connection ?? options.ref.provider;
  const subjectOf = (principal: EveConnectionPrincipal): CredentialSubject => {
    if (options.owner === "app") return { type: "app" };
    if (principal.type !== "user")
      throw new ConnectionAuthorizationRequiredError(name, {
        message: `Connection "${name}" needs a signed-in user`,
      });
    return principal.issuer === undefined
      ? { type: "user", id: principal.id }
      : { type: "user", id: principal.id, issuer: principal.issuer };
  };
  const displayName =
    options.connection === undefined ? {} : { displayName: options.connection };
  const getToken = async ({
    principal,
  }: EveConnectionRequest): Promise<EveTokenResult> => {
    const result = await options.provider.getToken(options.ref, {
      subject: subjectOf(principal),
      ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
    });
    if (!result.ok) throw connectionError(name, result.error);
    const { token, expiresAt } = result.data;
    return expiresAt === undefined
      ? { token }
      : { token, expiresAt: expiresAt.epochMilliseconds };
  };

  const { provider, ref } = options;
  if (
    options.owner === "app" ||
    options.interactive === false ||
    !provider.capabilities(ref).authorization ||
    !provider.startAuthorization ||
    !provider.completeAuthorization
  )
    return { credentialOwner: options.owner, ...displayName, getToken };
  const start = provider.startAuthorization.bind(provider);
  const complete = provider.completeAuthorization.bind(provider);
  return {
    principalType: "user",
    ...displayName,
    getToken,
    startAuthorization: async ({ principal, callbackUrl }) => {
      const result = await start(ref, {
        subject: subjectOf(principal),
        redirectUri: callbackUrl,
        ...(options.scopes === undefined ? {} : { scopes: options.scopes }),
      });
      if (!result.ok) throw connectionError(name, result.error);
      return { challenge: { url: result.data.url } };
    },
    completeAuthorization: async (request) => {
      const callback = new URL(request.callbackUrl);
      for (const [key, value] of Object.entries(request.callback.params))
        callback.searchParams.set(key, value);
      const result = await complete(ref, {
        subject: subjectOf(request.principal),
        callback,
      });
      if (!result.ok) throw connectionError(name, result.error);
      return getToken(request);
    },
  };
}

// ---------------------------------------------------------------------------
// File memory backend

/** eve's `MemoryDocumentConflictError`, matched by name. */
export class MemoryDocumentConflictError extends Error {
  override readonly name = "MemoryDocumentConflictError";
  readonly key: string;

  constructor(key: string) {
    super(`Memory document "${key}" changed since it was read`);
    this.key = key;
  }
}

/** The backend eve's `fileMemory({ backend })` reads and writes. */
export interface EveDocumentBackend {
  read(input: {
    readonly key: string;
    readonly signal?: AbortSignal;
  }): Promise<{ readonly content: string; readonly version: string } | null>;
  write(input: {
    readonly key: string;
    readonly content: string;
    readonly expectedVersion: string | null;
    readonly signal?: AbortSignal;
  }): Promise<{ readonly content: string; readonly version: string }>;
}

export interface SupabaseDocumentBackendOptions {
  /** `createMemory` on a service transport. */
  readonly memory: Memory;
  /** Prefixes every key, so apps can share the table. Defaults to `eve`. */
  readonly scope?: string;
}

const isConflict = (error: DbError): boolean =>
  "hint" in error && error.hint === "MEMORY_DOCUMENT_CONFLICT";

/**
 * A document backend for eve's `fileMemory()` over the memory module's
 * `memory_documents` table. A write with a stale version throws
 * `MemoryDocumentConflictError`, so eve retries with the current document.
 */
export function supabaseDocumentBackend(
  options: SupabaseDocumentBackendOptions,
): EveDocumentBackend {
  const scope = options.scope ?? "eve";
  return {
    read: async ({ key }) => {
      const result = await options.memory.documents.read(scope, key);
      if (!result.ok) throw new DbException(result.error);
      return result.data ?? null;
    },
    write: async ({ key, content, expectedVersion }) => {
      const result = await options.memory.documents.write(scope, key, content, {
        expectedVersion,
      });
      if (result.ok) return result.data;
      if (isConflict(result.error)) throw new MemoryDocumentConflictError(key);
      throw new DbException(result.error);
    },
  };
}

// ---------------------------------------------------------------------------
// Memory provider

interface EveMessagePart {
  readonly type: string;
  readonly text?: unknown;
}

interface EveModelMessage {
  readonly role: string;
  readonly content: string | readonly EveMessagePart[];
}

/** The context eve passes to a memory provider's handlers. */
export interface EveMemoryContext extends EveSessionContext {
  readonly memory: {
    readonly scope: { readonly key: string };
    readonly slot?: string;
  };
  readonly operationId: string;
  readonly messages?: readonly EveModelMessage[];
  readonly turn?: {
    readonly id: string;
    readonly input: readonly EveModelMessage[];
    readonly sequence?: number;
  } | null;
  readonly abortSignal?: AbortSignal;
}

export interface EveRecallMessage {
  readonly id?: string;
  readonly content: string;
}

export interface EveRecallResult {
  readonly messages: readonly EveRecallMessage[];
}

/** A provider for eve's `defineMemory({ provider })`; pass it through `defineMemoryProvider`. */
export interface EveMemoryProvider {
  readonly recall: {
    "turn.started"(ctx: EveMemoryContext): Promise<EveRecallResult | null>;
  };
  readonly capture?: {
    "turn.completed"?(ctx: EveMemoryContext): Promise<void>;
  };
  tools?(
    ctx: EveMemoryContext,
  ): Promise<Readonly<Record<string, unknown>> | null>;
}

export interface SupabaseMemoryOptions {
  /** `createMemory` on a service transport: eve calls the provider outside a user request. */
  readonly memory: Memory;
  /** Tenant documents to search alongside the memories. */
  readonly knowledge?: Knowledge;
  /**
   * The knowledge scopes to search. Defaults to the tenant's shared
   * documents: the provider searches as the service role, so a wider scope
   * can show one user's documents to another.
   */
  readonly knowledgeScopes?: KnowledgeSearchOptions["scopes"];
  /** Archival memories and knowledge chunks to recall per turn. Defaults to 5. */
  readonly k?: number;
  /** The tenant of a principal. Defaults to `attributes.tenantId`. */
  readonly organizationOf?: (auth: EveSessionAuth) => string | undefined;
  /**
   * Facts to keep from a finished turn (an LLM call of yours). Without it
   * the provider stores only what the model saves with its `remember` tool.
   */
  readonly extract?: (
    messages: readonly EveModelMessage[],
    ctx: EveMemoryContext,
  ) => Promise<readonly string[]>;
  /** Adds the `remember` and `forget` tools. Defaults to true. */
  readonly tools?: boolean;
  /** Returns `eve/tools`; defaults to importing it on first use. */
  readonly load?: () => Promise<unknown>;
}

const OPS_SCOPE = "eve-ops";
const OP_TTL_SECONDS = 7 * 24 * 60 * 60;

/** A UUID (version 8) from the SHA-256 of `input`, so the same input always gets the same id. */
export async function stableUuid(input: string): Promise<string> {
  const bytes = new Uint8Array(
    await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input)),
  ).slice(0, 16);
  bytes[6] = ((bytes[6] ?? 0) & 0x0f) | 0x80;
  bytes[8] = ((bytes[8] ?? 0) & 0x3f) | 0x80;
  const hex = [...bytes]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function textOfMessage(message: EveModelMessage): string {
  if (typeof message.content === "string") return message.content;
  return message.content
    .flatMap((part) =>
      part.type === "text" && typeof part.text === "string" ? [part.text] : [],
    )
    .join("\n");
}

interface EveToolsModule {
  readonly defineTool: (
    definition: Readonly<Record<string, unknown>>,
  ) => unknown;
}

const isToolsModule = (value: unknown): value is EveToolsModule =>
  isRecord(value) && typeof value["defineTool"] === "function";

/**
 * Loads `eve/tools` when the provider first builds its tools. The specifier
 * is a variable so bundlers leave the optional peer out.
 */
async function loadTools(): Promise<unknown> {
  const specifier = "eve/tools";
  try {
    return await import(specifier);
  } catch {
    return undefined;
  }
}

const isRecallResult = (value: unknown): value is EveRecallResult =>
  isRecord(value) &&
  Array.isArray(value["messages"]) &&
  value["messages"].every(
    (message) => isRecord(message) && typeof message["content"] === "string",
  );

/**
 * An eve memory provider over the memory and knowledge blocks. Every read
 * and write is partitioned by the scope key and the signed-in user; recall
 * stores its answer under the operation id, so a replayed recall returns the
 * same messages.
 */
export function supabaseMemory(
  options: SupabaseMemoryOptions,
): EveMemoryProvider {
  const { memory } = options;
  const k = options.k ?? 5;
  const organizationOf =
    options.organizationOf ??
    ((auth: EveSessionAuth) => {
      const tenant = auth.attributes["tenantId"];
      return typeof tenant === "string" ? tenant : undefined;
    });

  const target = async (
    ctx: EveMemoryContext,
  ): Promise<
    | { readonly organizationId: string; readonly namespace: MemoryNamespace }
    | undefined
  > => {
    const auth = ctx.session.auth.current;
    if (auth?.principalType !== "user") return undefined;
    const organizationId = organizationOf(auth);
    if (organizationId === undefined) return undefined;
    return {
      organizationId,
      namespace: {
        scope: "agent",
        agentId: await stableUuid(`eve-memory:${ctx.memory.scope.key}`),
        ownerId: auth.principalId,
      },
    };
  };

  const recall = async (
    ctx: EveMemoryContext,
    where: {
      readonly organizationId: string;
      readonly namespace: MemoryNamespace;
    },
  ): Promise<EveRecallResult> => {
    const query = (ctx.turn?.input ?? [])
      .filter((message) => message.role === "user")
      .map(textOfMessage)
      .join("\n")
      .trim();
    const [core, archival, documents] = await Promise.all([
      memory.render(where.organizationId, where.namespace).orThrow(),
      query.length === 0
        ? Promise.resolve([])
        : memory.archival
            .search(where.organizationId, query, where.namespace, { k })
            .orThrow(),
      query.length === 0 || !options.knowledge
        ? Promise.resolve([])
        : options.knowledge
            .search(where.organizationId, query, {
              k,
              scopes: options.knowledgeScopes ?? [{ scope: "organization" }],
            })
            .orThrow(),
    ]);
    const messages: EveRecallMessage[] = [];
    if (core.trim().length > 0) messages.push({ id: "core", content: core });
    for (const hit of archival)
      messages.push({ id: `memory:${hit.id}`, content: hit.content });
    for (const hit of documents)
      messages.push({
        id: `knowledge:${hit.documentId}:${String(hit.index)}`,
        content: hit.title ? `${hit.title}\n${hit.content}` : hit.content,
      });
    return { messages };
  };

  let tools: Promise<EveToolsModule> | undefined;
  const loaded = (): Promise<EveToolsModule> =>
    (tools ??= (options.load ?? loadTools)().then((value) => {
      if (!isToolsModule(value)) {
        tools = undefined;
        throw new TypeError(
          "supabaseMemory needs the eve package: pnpm add eve",
        );
      }
      return value;
    }));

  const provider: EveMemoryProvider = {
    recall: {
      "turn.started": async (ctx) => {
        const where = await target(ctx);
        if (!where) return null;
        const path = `recall/${ctx.operationId}`;
        const scopeKey = ctx.memory.scope.key;
        const stored = await memory.documents
          .read(OPS_SCOPE, `${scopeKey}/${path}`)
          .orThrow();
        if (stored) {
          const value: unknown = JSON.parse(stored.content);
          return isRecallResult(value) ? value : null;
        }
        const result = await recall(ctx, where);
        const written = await memory.documents.write(
          OPS_SCOPE,
          `${scopeKey}/${path}`,
          JSON.stringify(result),
          { expectedVersion: null, expiresIn: OP_TTL_SECONDS },
        );
        if (written.ok) return result;
        if (!isConflict(written.error)) throw new DbException(written.error);
        const raced = await memory.documents
          .read(OPS_SCOPE, `${scopeKey}/${path}`)
          .orThrow();
        const value: unknown = raced ? JSON.parse(raced.content) : null;
        return isRecallResult(value) ? value : null;
      },
    },
    ...(options.extract
      ? {
          capture: {
            "turn.completed": async (ctx: EveMemoryContext) => {
              const extract = options.extract;
              const where = await target(ctx);
              if (!extract || !where) return;
              const marker = `${ctx.memory.scope.key}/capture/${ctx.operationId}`;
              if (await memory.documents.read(OPS_SCOPE, marker).orThrow())
                return;
              const facts = await extract(ctx.messages ?? [], ctx);
              if (facts.length > 0)
                await memory
                  .saveExtracted(where.organizationId, facts, where.namespace, {
                    sourceMessageId: ctx.operationId,
                  })
                  .orThrow();
              const written = await memory.documents.write(
                OPS_SCOPE,
                marker,
                "{}",
                {
                  expectedVersion: null,
                  expiresIn: OP_TTL_SECONDS,
                },
              );
              if (!written.ok && !isConflict(written.error))
                throw new DbException(written.error);
            },
          },
        }
      : {}),
  };
  if (options.tools === false) return provider;
  return {
    ...provider,
    tools: async (ctx) => {
      const where = await target(ctx);
      if (!where) return null;
      const { defineTool } = await loaded();
      return {
        remember: defineTool({
          description:
            "Save a fact about the user to recall in later conversations.",
          inputSchema: {
            type: "object",
            properties: {
              fact: { type: "string", minLength: 1, maxLength: 2000 },
            },
            required: ["fact"],
            additionalProperties: false,
          },
          execute: async (input: Readonly<Record<string, unknown>>) => {
            const fact = typeof input["fact"] === "string" ? input["fact"] : "";
            const saved = await memory.archival
              .save(where.organizationId, fact, where.namespace)
              .orThrow();
            return { id: saved.id };
          },
        }),
        forget: defineTool({
          description: "Delete a remembered fact by the id shown with it.",
          inputSchema: {
            type: "object",
            properties: { id: { type: "string", minLength: 1 } },
            required: ["id"],
            additionalProperties: false,
          },
          execute: async (input: Readonly<Record<string, unknown>>) => {
            const id =
              typeof input["id"] === "string"
                ? input["id"].replace(/^memory:/, "")
                : "";
            const page = await memory.archival
              .list(where.organizationId, where.namespace, { limit: 1000 })
              .orThrow();
            if (!page.some((record) => record.id === id))
              return { deleted: false };
            return { deleted: await memory.archival.forget(id).orThrow() };
          },
        }),
      };
    },
  };
}

// ---------------------------------------------------------------------------
// Session persistence

interface EveEvent<T> {
  readonly type?: string;
  readonly data: T;
  readonly meta?: { readonly id?: string; readonly at?: string };
}

interface TurnData {
  readonly turnId: string;
  readonly sequence: number;
}

/** Hook handlers for eve's `defineHook({ events })`. */
export interface EveSessionHooks {
  "session.started"(
    event: EveEvent<unknown>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.started"(
    event: EveEvent<TurnData>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "message.received"(
    event: EveEvent<TurnData & { readonly message: string }>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "message.completed"(
    event: EveEvent<
      TurnData & {
        readonly message: string;
        readonly stepIndex: number;
        readonly finishReason: string;
      }
    >,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.completed"(
    event: EveEvent<TurnData>,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.failed"(
    event: EveEvent<
      TurnData & { readonly code: string; readonly message: string }
    >,
    ctx: EveSessionContext,
  ): Promise<void>;
  "turn.cancelled"(
    event: EveEvent<TurnData>,
    ctx: EveSessionContext,
  ): Promise<void>;
}

export interface PersistSessionsOptions {
  /** `createAiChat` on a service transport. */
  readonly chats: AiChat;
  /** The tenant of a principal. Defaults to `attributes.tenantId`. */
  readonly organizationOf?: (auth: EveSessionAuth) => string | undefined;
  readonly agentId?: string;
  /** The title of a new chat. Defaults to `eve session`. */
  readonly title?: string;
}

/** The `ai_chats` id of an eve session: the same session always maps to the same chat. */
export function chatIdOf(sessionId: string): Promise<string> {
  return stableUuid(`eve-session:${sessionId}`);
}

const streamOf = (sessionId: string, turnId: string): string =>
  `eve:${sessionId}:${turnId}`;

/**
 * Hook handlers that copy an eve session into the canonical chat tables, so
 * the chat UI, search, memory recall and analytics read eve sessions like any
 * other chat. Every write is keyed by the event, so eve's at-least-once
 * delivery stores each message once. Sessions without a signed-in user and
 * tenant are skipped.
 */
export function persistSessions(
  options: PersistSessionsOptions,
): EveSessionHooks {
  const { chats } = options;
  const organizationOf =
    options.organizationOf ??
    ((auth: EveSessionAuth) => {
      const tenant = auth.attributes["tenantId"];
      return typeof tenant === "string" ? tenant : undefined;
    });

  const chatFor = async (
    ctx: EveSessionContext,
  ): Promise<string | undefined> => {
    const auth = ctx.session.auth.initiator ?? ctx.session.auth.current;
    if (auth?.principalType !== "user") return undefined;
    const organizationId = organizationOf(auth);
    if (organizationId === undefined) return undefined;
    const id = await chatIdOf(ctx.session.id);
    await chats.chats
      .create(organizationId, {
        id,
        ownerId: auth.principalId,
        title: options.title ?? "eve session",
        ...(options.agentId === undefined ? {} : { agentId: options.agentId }),
      })
      .orThrow();
    return id;
  };

  const knownChat = async (
    ctx: EveSessionContext,
  ): Promise<string | undefined> => {
    const auth = ctx.session.auth.initiator ?? ctx.session.auth.current;
    if (auth?.principalType !== "user" || organizationOf(auth) === undefined)
      return undefined;
    return chatIdOf(ctx.session.id);
  };

  const release = async (
    ctx: EveSessionContext,
    turnId: string,
    status: "done" | "error" | "stopped",
    error?: string,
  ): Promise<void> => {
    const chatId = await knownChat(ctx);
    if (chatId === undefined) return;
    await chats.runs
      .release(chatId, streamOf(ctx.session.id, turnId), {
        status,
        ...(error === undefined ? {} : { error }),
      })
      .orThrow();
  };

  return {
    "session.started": async (_event, ctx) => {
      await chatFor(ctx);
    },
    "turn.started": async (event, ctx) => {
      const chatId = await chatFor(ctx);
      if (chatId === undefined) return;
      await chats.runs
        .claim(chatId, streamOf(ctx.session.id, event.data.turnId), {
          engine: "eve",
        })
        .orThrow();
    },
    "message.received": async (event, ctx) => {
      const chatId = await chatFor(ctx);
      if (chatId === undefined || event.data.message.length === 0) return;
      const id = `${event.data.turnId}:${String(event.data.sequence)}`;
      await chats.messages
        .appendUser(chatId, {
          id,
          role: "user",
          parts: [{ type: "text", text: event.data.message }],
        })
        .orThrow();
    },
    "message.completed": async (event, ctx) => {
      const chatId = await knownChat(ctx);
      if (chatId === undefined || event.data.message.length === 0) return;
      const chat = await chats.chats.get(chatId).orThrow();
      if (chat.leafId === undefined) return;
      const id = `${event.data.turnId}:${String(event.data.stepIndex)}:${String(event.data.sequence)}`;
      await chats.messages
        .saveAssistant(
          chatId,
          {
            id,
            role: "assistant",
            parts: [{ type: "text", text: event.data.message }],
            ...(event.data.finishReason === "tool-calls"
              ? { metadata: { interim: true } }
              : {}),
          },
          {
            parentId: chat.leafId,
            status: "complete",
            format: "eve",
            native: event.data,
            runId: chat.activeRunId,
          },
        )
        .orThrow();
    },
    "turn.completed": (event, ctx) => release(ctx, event.data.turnId, "done"),
    "turn.failed": (event, ctx) =>
      release(
        ctx,
        event.data.turnId,
        "error",
        `${event.data.code}: ${event.data.message}`,
      ),
    "turn.cancelled": (event, ctx) =>
      release(ctx, event.data.turnId, "stopped"),
  };
}

// ---------------------------------------------------------------------------
// Inbox channel

/** The parts of a Chat SDK thread `routeInbox` reads. */
export interface EveChatThread {
  readonly id: string;
  subscribe(): Promise<void>;
}

/** The parts of a Chat SDK message `routeInbox` reads. */
export interface EveChatMessage {
  readonly text: string;
}

/** The parts of eve's `chatSdkChannel()` result `routeInbox` uses. */
export interface EveChatSdkBridge {
  readonly bot: {
    onNewMention(
      handler: (
        thread: EveChatThread,
        message: EveChatMessage,
      ) => Promise<void>,
    ): void;
    onSubscribedMessage(
      handler: (
        thread: EveChatThread,
        message: EveChatMessage,
      ) => Promise<void>,
    ): void;
  };
  send(
    message: string,
    options: {
      readonly thread: EveChatThread;
      readonly auth: EveSessionAuth | null;
      readonly title?: string;
    },
  ): Promise<unknown>;
}

export interface RouteInboxOptions {
  /** `createInbox` on a service transport. */
  readonly inbox: Inbox;
  /** The session title for a new conversation. Defaults to the conversation's subject. */
  readonly title?: string;
}

const INBOX_PREFIX = "inbox:";

/**
 * Hands inbox conversations to eve through a `chatSdkChannel` built over
 * `inboxAdapter`. A message reaches eve only while the conversation's
 * `bot_mode` is `bot`, so an agent's handoff pauses the bot. The turn's
 * principal is the contact, never a user, so contacts get no user-scoped
 * connections.
 */
export function routeInbox(
  bridge: EveChatSdkBridge,
  options: RouteInboxOptions,
): void {
  const handle = async (
    thread: EveChatThread,
    message: EveChatMessage,
  ): Promise<void> => {
    if (!thread.id.startsWith(INBOX_PREFIX)) return;
    const conversation = await options.inbox.conversations
      .get(thread.id.slice(INBOX_PREFIX.length))
      .orThrow();
    if (conversation?.botMode !== "bot") return;
    const title = options.title ?? conversation.subject ?? undefined;
    await bridge.send(message.text, {
      thread,
      auth: {
        authenticator: "inbox",
        principalType: "contact",
        principalId: conversation.contactId,
        attributes: {
          tenantId: conversation.tenant,
          conversationId: conversation.id,
        },
      },
      ...(title === undefined ? {} : { title }),
    });
  };
  bridge.bot.onNewMention(async (thread, message) => {
    await thread.subscribe();
    await handle(thread, message);
  });
  bridge.bot.onSubscribedMessage(handle);
}
