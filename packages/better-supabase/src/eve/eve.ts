import type {
  Knowledge,
  KnowledgeSearchOptions,
} from "../blocks/knowledge/knowledge.ts";
import type { Memory, MemoryNamespace } from "../blocks/memory/memory.ts";
import type { EveSessionAuth, EveSessionContext } from "./types.ts";

import { isRecord } from "../core/block-helpers.ts";
import { type DbError, DbException } from "../core/errors.ts";
import { stableUuid } from "./ids.ts";

export { EveAuthRejection, principalOf, supabaseAuth } from "./auth.ts";
export type { SupabaseAuthOptions } from "./auth.ts";
export {
  ConnectionAuthorizationFailedError,
  ConnectionAuthorizationRequiredError,
  credentialAuth,
} from "./connections.ts";
export type {
  CredentialAuthOptions,
  EveAuthorizationChallenge,
  EveConnectionAuthorization,
  EveConnectionPrincipal,
  EveConnectionRequest,
  EveInteractiveAuthorization,
  EveTokenAuthorization,
  EveTokenResult,
} from "./connections.ts";
export { stableUuid } from "./ids.ts";
export { routeInbox } from "./inbox.ts";
export type {
  EveChatMessage,
  EveChatSdkBridge,
  EveChatThread,
  RouteInboxOptions,
} from "./inbox.ts";
export { chatIdOf, persistSessions } from "./sessions.ts";
export type { EveSessionHooks, PersistSessionsOptions } from "./sessions.ts";
export type { EveSessionAuth, EveSessionContext } from "./types.ts";

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
  /** The document backend contract version. Omitted means 1. */
  readonly apiVersion?: 1;
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
    apiVersion: 1,
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

/** The context eve passes to a memory provider's `tools`. */
export interface EveMemoryToolsContext extends EveSessionContext {
  readonly memory: {
    readonly scope: { readonly key: string };
    readonly slot?: string;
  };
}

/** The context eve passes to a memory provider's recall and capture handlers. */
export interface EveMemoryContext extends EveMemoryToolsContext {
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
    ctx: EveMemoryToolsContext,
  ): Promise<Readonly<Record<string, EveMemoryTool>> | null>;
}

/** A tool from eve's `defineTool`, as a memory provider returns it. */
export interface EveMemoryTool {
  readonly description: string;
  readonly inputSchema: unknown;
  execute(input: never, context: never): unknown;
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

function textOfMessage(message: EveModelMessage): string {
  if (typeof message.content === "string") return message.content;
  return message.content
    .flatMap((part) =>
      part.type === "text" && typeof part.text === "string" ? [part.text] : [],
    )
    .join("\n");
}

interface EveToolsModule {
  readonly defineTool: (definition: EveMemoryTool) => EveMemoryTool;
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
    ctx: EveMemoryToolsContext,
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
