import type {
  Knowledge,
  KnowledgeSearchOptions,
} from "../blocks/knowledge/knowledge.ts";
import type { Memory, MemoryNamespace } from "../blocks/memory/memory.ts";
import type { DbError } from "../core/errors.ts";
import type { RecordRef } from "../schema/types.ts";
import type { EveSessionAuth, EveSessionContext } from "./types.ts";

import { isRecord } from "../core/block-helpers.ts";
import { DbException } from "../core/errors.ts";
import { importOptionalPeer } from "../core/optional-peer.ts";
import { stableUuid } from "./ids.ts";

export { approvalPolicy } from "./approvals.ts";

export type { ApprovalPolicyOptions, EveApprovalsClient } from "./approvals.ts";

export {
  EveAuthRejection,
  principalOf,
  supabaseAuth,
  supabaseJwtAuth,
} from "./auth.ts";

export type { SupabaseAuthOptions, SupabaseJwtAuthOptions } from "./auth.ts";

export {
  ConnectionAuthorizationFailedError,
  ConnectionAuthorizationRequiredError,
  credentialAuth,
  openApiAuth,
  tenantArgument,
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

export {
  eveScheduleRun,
  queueDynamicSchedules,
  queueScheduleProvider,
  validateExpression,
} from "./dynamic-schedules.ts";

export type {
  EveDynamicRunParams,
  EveDynamicSchedules,
  EveDynamicTargetHandle,
  EveScheduleAuthContext,
  EveScheduleExpression,
  EveScheduleFailureNotice,
  EveScheduleHandle,
  EveScheduleJob,
  EveScheduleOccurrence,
  EveScheduleOccurrenceEvent,
  EveScheduleOccurrenceIdentity,
  EveSchedulePrincipal,
  EveScheduleProvider,
  EveScheduleProviderContext,
  EveScheduleRecord,
  EveScheduleRun,
  EveScheduleScopeRule,
  EveScheduleState,
  QueueDynamicSchedulesOptions,
  QueueScheduleProviderOptions,
  ValidateExpressionOptions,
} from "./dynamic-schedules.ts";

export { stableUuid } from "./ids.ts";

export { routeInbox } from "./inbox.ts";

export type {
  EveChatMessage,
  EveChatSdkBridge,
  EveChatThread,
  RouteInboxOptions,
} from "./inbox.ts";

export {
  agentJobHandler,
  aiScheduleDispatch,
  eveAgentJob,
  jobAuth,
  queueSchedules,
  scheduleAgent,
} from "./schedules.ts";

export type {
  AgentJobOptions,
  AiScheduleDispatch,
  AiScheduleDispatchOptions,
  EveAgentJob,
  EveDispatchOptions,
  EveQueueDrainer,
  EveQueueJob,
  EveQueueScheduler,
  EveScheduleOptions,
  EveSendOptions,
  EveTargetHandle,
  QueueSchedulesOptions,
  ScheduleAgentOptions,
} from "./schedules.ts";

export { chatIdOf, persistSessions } from "./sessions.ts";

export type { EveSessionHooks, PersistSessionsOptions } from "./sessions.ts";

export { eveContext, supabaseTool, tenantToolApproval } from "./tools.ts";

export type {
  EveContextOptions,
  EveContextRunner,
  EveRunAs,
  EveToolPolicySource,
  SupabaseToolCall,
  SupabaseToolDefinition,
  SupabaseToolOptions,
} from "./tools.ts";

export type {
  EveApprovalConfiguration,
  EveApprovalContext,
  EveApprovalPolicy,
  EveApprovalResponseContext,
  EveApprovalResponseDecision,
  EveApprovalStatus,
  EveSessionAuth,
  EveSessionContext,
  EveToolApproval,
  EveToolContext,
} from "./types.ts";

// ---------------------------------------------------------------------------
// File memory backend

/** Eve's `MemoryDocumentConflictError`, matched by name. */
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
      const result = await options.memory.documents.read({
        scopeKey: scope,
        path: key,
      });

      if (!result.ok) {
        throw new DbException(result.error);
      }

      return result.data ?? null;
    },
    write: async ({ key, content, expectedVersion }) => {
      const result = await options.memory.documents.write({
        scopeKey: scope,
        path: key,
        content,
        options: { expectedVersion },
      });

      if (result.ok) {
        return result.data;
      }

      if (isConflict(result.error)) {
        throw new MemoryDocumentConflictError(key);
      }

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

/**
 * A provider for eve's `defineMemory({ provider })`; pass it through
 * `defineMemoryProvider`.
 */
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

/** A JSON value, as eve's `JsonObject` tool schemas hold. */
export type EveJsonValue =
  | string
  | number
  | boolean
  | null
  | readonly EveJsonValue[]
  | { readonly [key: string]: EveJsonValue };

/** A tool from eve's `defineTool`, as a memory provider returns it. */
export interface EveMemoryTool {
  readonly description: string;
  /** A JSON Schema object, as the memory tools here declare their input. */
  readonly inputSchema: { readonly [key: string]: EveJsonValue };
  execute(input: never, context: never): unknown;
}

export interface SupabaseMemoryOptions {
  /**
   * `createMemory` on a service transport: eve calls the provider outside a
   * user request.
   */
  readonly memory: Memory;
  /** Tenant documents to search alongside the memories. */
  readonly knowledge?: Knowledge;
  /**
   * The knowledge scopes to search. Defaults to the tenant's shared documents:
   * the provider searches as the service role, so a wider scope can show one
   * user's documents to another.
   */
  readonly knowledgeScopes?: KnowledgeSearchOptions["scopes"];
  /** Archival memories and knowledge chunks to recall per turn. Defaults to 5. */
  readonly k?: number;
  /** The tenant of a principal. Defaults to `attributes.tenantId`. */
  readonly organizationOf?: (auth: EveSessionAuth) => string | undefined;
  /**
   * The memory scopes to recall from and write to, in this order. Defaults to
   * `["user"]`, the signed-in user's own memory. `"organization"` is shared by
   * the tenant and `{ record }` names one record, such as the inbox contact the
   * conversation is about. Shared scopes are read-only unless the entry sets
   * `write: true`: the provider runs as the service role, so a writable shared
   * scope lets the model change what every user of the tenant recalls.
   */
  readonly scopes?: readonly EveMemoryScopeOption[];
  /**
   * Facts to keep from a finished turn (an LLM call of yours). Without it the
   * provider stores only what the model saves with its `remember` tool.
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

/** One entry of `supabaseMemory({ scopes })`. */
export type EveMemoryScopeOption =
  | "user"
  | "organization"
  | {
      readonly scope: "user" | "organization";
      /** Lets the `remember` and `forget` tools change this scope. */
      readonly write?: boolean;
    }
  | {
      readonly scope: "record";
      /** The record the conversation is about, or `undefined` for none. */
      readonly subject: (
        ctx: EveMemoryToolsContext,
        auth: EveSessionAuth | undefined,
      ) => RecordRef | undefined | Promise<RecordRef | undefined>;
      readonly write?: boolean;
    };

interface MemoryTarget {
  readonly name: string;
  readonly organizationId: string;
  readonly namespace: MemoryNamespace;
  readonly write: boolean;
}

const OPS_SCOPE = "eve-ops";
const OP_TTL_SECONDS = 7 * 24 * 60 * 60;

function textOfMessage(message: EveModelMessage): string {
  if (typeof message.content === "string") {
    return message.content;
  }

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
 * Loads `eve/tools` when the provider first builds its tools. The specifier is
 * a variable so bundlers leave the optional peer out.
 */
const loadTools = (): Promise<unknown> => importOptionalPeer("eve/tools");

const isRecallResult = (value: unknown): value is EveRecallResult =>
  isRecord(value) &&
  Array.isArray(value["messages"]) &&
  value["messages"].every(
    (message) => isRecord(message) && typeof message["content"] === "string",
  );

/**
 * An eve memory provider over the memory and knowledge blocks. Every read and
 * write is partitioned by the scope key and the signed-in user; recall stores
 * its answer under the operation id, so a replayed recall returns the same
 * messages.
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

  const scopes: readonly EveMemoryScopeOption[] = options.scopes ?? ["user"];

  if (scopes.length === 0) {
    throw new TypeError("supabaseMemory({ scopes }) needs at least one scope");
  }

  const targets = async (
    ctx: EveMemoryToolsContext,
  ): Promise<readonly MemoryTarget[]> => {
    const auth = ctx.session.auth.current;

    const organizationId = auth === null ? undefined : organizationOf(auth);

    if (organizationId === undefined) {
      return [];
    }

    const found: MemoryTarget[] = [];

    for (const entry of scopes) {
      const spec = typeof entry === "string" ? { scope: entry } : entry;

      switch (spec.scope) {
        case "user": {
          if (auth?.principalType !== "user") {
            break;
          }

          found.push({
            name: "user",
            organizationId,
            namespace: {
              scope: "agent",
              agentId: await stableUuid(`eve-memory:${ctx.memory.scope.key}`),
              ownerId: auth.principalId,
            },
            write: !("write" in spec) || spec.write,
          });
          break;
        }

        case "organization": {
          found.push({
            name: "organization",
            organizationId,
            namespace: { scope: "organization" },
            write: "write" in spec && spec.write,
          });
          break;
        }

        case "record": {
          const subject = await spec.subject(ctx, auth ?? undefined);

          if (subject !== undefined) {
            found.push({
              name: `record:${subject.type}`,
              organizationId,
              namespace: { scope: "record", subject },
              write: spec.write === true,
            });
          }

          break;
        }

        default: {
          const never: never = spec;

          throw new TypeError(`Unknown memory scope ${JSON.stringify(never)}`);
        }
      }
    }

    return found;
  };

  const recall = async (
    ctx: EveMemoryContext,
    found: readonly MemoryTarget[],
  ): Promise<EveRecallResult> => {
    const query = (ctx.turn?.input ?? [])
      .filter((message) => message.role === "user")
      .map(textOfMessage)
      .join("\n")
      .trim();

    const perScope = await Promise.all(
      found.map(async (where) => {
        const [core, archival] = await Promise.all([
          memory
            .render({
              organizationId: where.organizationId,
              ns: where.namespace,
            })
            .orThrow(),
          query.length === 0
            ? Promise.resolve([])
            : memory.archival
                .search({
                  organizationId: where.organizationId,
                  query,
                  ns: where.namespace,
                  k,
                })
                .orThrow(),
        ]);

        return { name: where.name, core, archival };
      }),
    );

    const first = found[0];

    const documents =
      query.length === 0 || !options.knowledge || first === undefined
        ? []
        : await options.knowledge
            .search({
              organizationId: first.organizationId,
              query,
              k,
              scopes: options.knowledgeScopes ?? [{ scope: "organization" }],
            })
            .orThrow();

    const messages: EveRecallMessage[] = [];

    for (const [index, entry] of perScope.entries()) {
      if (entry.core.trim().length > 0) {
        // The first scope keeps the id earlier releases used.
        messages.push({
          id: index === 0 ? "core" : `core:${entry.name}`,
          content: entry.core,
        });
      }

      for (const hit of entry.archival) {
        messages.push({ id: `memory:${hit.id}`, content: hit.content });
      }
    }

    for (const hit of documents) {
      messages.push({
        id: `knowledge:${hit.documentId}:${String(hit.index)}`,
        content: hit.title ? `${hit.title}\n${hit.content}` : hit.content,
      });
    }

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
        const found = await targets(ctx);

        if (found.length === 0) {
          return null;
        }

        const path = `recall/${ctx.operationId}`;
        const scopeKey = ctx.memory.scope.key;

        const stored = await memory.documents
          .read({ scopeKey: OPS_SCOPE, path: `${scopeKey}/${path}` })
          .orThrow();

        if (stored) {
          const value: unknown = JSON.parse(stored.content);

          return isRecallResult(value) ? value : null;
        }

        const result = await recall(ctx, found);

        const written = await memory.documents.write({
          scopeKey: OPS_SCOPE,
          path: `${scopeKey}/${path}`,
          content: JSON.stringify(result),
          options: { expectedVersion: null, expiresIn: OP_TTL_SECONDS },
        });

        if (written.ok) {
          return result;
        }

        if (!isConflict(written.error)) {
          throw new DbException(written.error);
        }

        const raced = await memory.documents
          .read({ scopeKey: OPS_SCOPE, path: `${scopeKey}/${path}` })
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
              const where = (await targets(ctx)).find((entry) => entry.write);

              if (!extract || !where) {
                return;
              }

              const marker = `${ctx.memory.scope.key}/capture/${ctx.operationId}`;

              if (
                await memory.documents
                  .read({ scopeKey: OPS_SCOPE, path: marker })
                  .orThrow()
              ) {
                return;
              }

              const facts = await extract(ctx.messages ?? [], ctx);

              if (facts.length > 0) {
                await memory
                  .saveExtracted({
                    organizationId: where.organizationId,
                    facts,
                    ns: where.namespace,
                    sourceMessageId: ctx.operationId,
                  })
                  .orThrow();
              }

              const written = await memory.documents.write({
                scopeKey: OPS_SCOPE,
                path: marker,
                content: "{}",
                options: { expectedVersion: null, expiresIn: OP_TTL_SECONDS },
              });

              if (!written.ok && !isConflict(written.error)) {
                throw new DbException(written.error);
              }
            },
          },
        }
      : {}),
  };

  if (options.tools === false) {
    return provider;
  }

  return {
    ...provider,
    tools: async (ctx) => {
      const writable = (await targets(ctx)).filter((entry) => entry.write);
      const first = writable[0];

      if (first === undefined) {
        return null;
      }

      const { defineTool } = await loaded();
      const names = writable.map((entry) => entry.name);

      const scopeProperty: { readonly [key: string]: EveJsonValue } =
        writable.length > 1
          ? {
              scope: {
                type: "string",
                enum: names,
                description: `Where to keep it. Defaults to ${first.name}.`,
              },
            }
          : {};

      const pick = (input: Readonly<Record<string, unknown>>): MemoryTarget =>
        writable.find((entry) => entry.name === input["scope"]) ?? first;

      return {
        remember: defineTool({
          description:
            "Save a fact about the user to recall in later conversations.",
          inputSchema: {
            type: "object",
            properties: {
              fact: { type: "string", minLength: 1, maxLength: 2000 },
              ...scopeProperty,
            },
            required: ["fact"],
            additionalProperties: false,
          },
          execute: async (input: Readonly<Record<string, unknown>>) => {
            const fact = typeof input["fact"] === "string" ? input["fact"] : "";
            const where = pick(input);

            const saved = await memory.archival
              .upsert({
                organizationId: where.organizationId,
                content: fact,
                ns: where.namespace,
              })
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

            for (const where of writable) {
              const page = await memory.archival
                // oxlint-disable-next-line typescript/no-deprecated -- the deprecated alias stays in use until 0.70 (ADR 1077)
                .list({
                  organizationId: where.organizationId,
                  ns: where.namespace,
                  limit: 1000,
                })
                .orThrow();

              if (page.some((record) => record.id === id)) {
                return {
                  deleted: await memory.archival
                    .forget({ memoryId: id })
                    .orThrow(),
                };
              }
            }

            return { deleted: false };
          },
        }),
      };
    },
  };
}
