import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { AiMessage, AiMessageRole } from "./message.ts";

import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  oneOf,
} from "../shared.ts";
import {
  approvalOf,
  record,
  instant,
  chatOf,
  projectOf,
  ROLES,
  storedOf,
  savedOf,
  policyOf,
  inputOf,
  feedbackOf,
  shareOf,
  sharedOf,
  modelOf,
  moderationOf,
  chatFields,
  patchFields,
  projectFields,
  canonical,
} from "./rows.ts";

export type AiChatVisibility = "private" | "organization";

export interface AiChatRecord {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string;
  readonly projectId: string | undefined;
  readonly agentId: string | undefined;
  readonly title: string;
  readonly model: string | undefined;
  readonly visibility: AiChatVisibility;
  readonly pinned: boolean;
  readonly archivedAt: Temporal.Instant | undefined;
  /** A temporary chat expires at `expiresAt` and never reaches the chat list. */
  readonly temporary: boolean;
  readonly expiresAt: Temporal.Instant | undefined;
  /** The message the chat shows: the end of the active branch. */
  readonly leafId: string | undefined;
  /** The stream of the answer being written, while one runs. */
  readonly activeStreamId: string | undefined;
  readonly activeRunId: string | undefined;
  readonly lastMessageAt: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AiChatInput {
  /** A client-made id, so a retried create returns the same chat. */
  readonly id?: string;
  readonly title?: string;
  readonly model?: string | null;
  readonly projectId?: string | null;
  readonly agentId?: string | null;
  /** `organization` needs `ai_chat.share`. */
  readonly visibility?: AiChatVisibility;
  readonly pinned?: boolean;
  readonly temporary?: boolean;
  /** The service role only: the user the chat belongs to. */
  readonly ownerId?: string;
}

export interface AiChatPatch {
  readonly title?: string;
  readonly model?: string | null;
  readonly projectId?: string | null;
  readonly visibility?: AiChatVisibility;
  readonly pinned?: boolean;
  readonly archived?: boolean;
}

export interface AiChatQuery {
  readonly organizationId?: string | null;
  /** Full-text search over titles and message text. */
  readonly search?: string;
  readonly projectId?: string;
  readonly pinned?: boolean;
  readonly archived?: boolean;
  /** The `next` cursor of the previous page. */
  readonly after?: string;
  readonly size?: number;
}

export interface AiChatPage {
  readonly items: readonly AiChatRecord[];
  /** Pass as `after` for the next page; `undefined` on the last one. */
  readonly next: string | undefined;
}

export interface AiProject {
  readonly id: string;
  readonly organizationId: string;
  readonly ownerId: string;
  readonly name: string;
  readonly instructions: string;
  readonly defaultModel: string | undefined;
  readonly pinned: boolean;
  readonly archivedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface AiProjectInput {
  readonly name?: string;
  readonly instructions?: string;
  readonly defaultModel?: string | null;
  readonly pinned?: boolean;
  readonly archived?: boolean;
}

export type AiStoredMessageStatus = "complete" | "aborted" | "error";

/** A message as the tree stores it: the canonical fields plus its place. */
export interface AiStoredMessage extends AiMessage {
  readonly parentId: string | undefined;
  /** `canonical`, or the format `native` holds (such as `ai-sdk-ui`). */
  readonly format: string;
  /** The SDK's own message, when `path(..., { native: true })` asks for it. */
  readonly native: unknown;
  readonly model: string | undefined;
  readonly status: AiStoredMessageStatus;
  readonly createdAt: Temporal.Instant;
  /** How many messages share this one's parent, itself included. */
  readonly siblingCount: number;
  /** Its position among them, from 0, oldest first. */
  readonly siblingIndex: number;
}

export interface AiMessageSibling {
  readonly id: string;
  readonly role: AiMessageRole;
  readonly createdAt: Temporal.Instant;
}

export type AiUserMessageTrigger = "submit-message" | "regenerate-message";

export interface AiAppendResult {
  /** The stored id: a fresh one when the message edits an earlier one. */
  readonly messageId: string;
  readonly parentId: string | undefined;
  /** `false` for a retry, or for `regenerate-message`, which adds nothing. */
  readonly created: boolean;
}

export interface AiAssistantMessageOptions {
  readonly parentId: string;
  readonly status?: AiStoredMessageStatus;
  readonly model?: string;
  /** The format of `native`, such as `ai-sdk-ui`. */
  readonly format?: string;
  readonly native?: unknown;
  /** The run `runs.claim` returned. */
  readonly runId?: string | undefined;
}

export interface AiSaveResult {
  readonly messageId: string;
  readonly parentId: string | undefined;
  readonly created: boolean;
}

export interface AiStreamClaim {
  /** `false` while another live stream writes the chat's answer. */
  readonly claimed: boolean;
  readonly streamId: string | undefined;
  readonly runId: string | undefined;
}

export type AiRunStatus = "done" | "error" | "stopped";

export interface AiRunRelease {
  readonly status?: AiRunStatus;
  readonly usage?: Readonly<Record<string, unknown>>;
  readonly generationId?: string;
  readonly error?: string;
  readonly costMicroUsd?: number;
}

export type AiApprovalDecision = "pending" | "approved" | "denied";

export interface AiToolApproval {
  readonly approvalId: string;
  readonly chatId: string;
  readonly runId: string | undefined;
  readonly messageId: string | undefined;
  readonly tool: string;
  readonly toolCallId: string;
  readonly input: unknown;
  readonly decision: AiApprovalDecision;
  readonly reason: string | undefined;
  readonly signature: string | undefined;
  readonly decidedBy: string | undefined;
  readonly decidedAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface AiToolApprovalRequest {
  readonly approvalId: string;
  readonly tool: string;
  readonly toolCallId: string;
  readonly input?: unknown;
  readonly runId?: string;
  readonly messageId?: string;
  /** A signature over the input, so the decision can't be replayed on other input. */
  readonly signature?: string;
}

export type AiToolPolicy = "auto" | "ask" | "deny";

export interface AiPendingInput {
  readonly id: string;
  readonly chatId: string;
  readonly runId: string | undefined;
  readonly toolCallId: string | undefined;
  readonly question: string;
  /** A JSON Schema for the answer. */
  readonly schema: unknown;
  readonly answer: unknown;
  readonly answeredAt: Temporal.Instant | undefined;
  readonly createdAt: Temporal.Instant;
}

export interface AiPendingInputRequest {
  readonly question: string;
  readonly schema?: unknown;
  readonly runId?: string;
  readonly toolCallId?: string;
}

export interface AiFeedback {
  readonly chatId: string;
  readonly messageId: string;
  /** `1` up, `-1` down, `0` cleared. */
  readonly rating: -1 | 0 | 1;
  readonly reason: string | undefined;
  readonly comment: string | undefined;
}

export interface AiChatShare {
  readonly id: string;
  readonly leafId: string;
  readonly createdBy: string | undefined;
  readonly createdAt: Temporal.Instant;
  readonly revokedAt: Temporal.Instant | undefined;
}

/** A new share link. The token is shown once; only its hash is stored. */
export interface AiShareLink {
  readonly id: string;
  readonly token: string;
  readonly leafId: string;
  readonly createdAt: Temporal.Instant;
}

export interface SharedAiChat {
  readonly chat: {
    readonly id: string;
    readonly title: string;
    readonly model: string | undefined;
    readonly createdAt: Temporal.Instant;
  };
  readonly leafId: string;
  readonly messages: readonly AiStoredMessage[];
}

export interface AiModel {
  readonly id: string;
  readonly provider: string;
  readonly name: string;
  readonly pricing: Readonly<Record<string, unknown>>;
  readonly capabilities: Readonly<Record<string, unknown>>;
  /** Entitlement keys that unlock it; empty for every tenant. */
  readonly plans: readonly string[];
  readonly enabled: boolean;
  readonly refreshedAt: Temporal.Instant | undefined;
}

export interface AiModelInput {
  readonly id: string;
  readonly provider?: string;
  readonly name?: string;
  readonly pricing?: Readonly<Record<string, unknown>>;
  readonly capabilities?: Readonly<Record<string, unknown>>;
  readonly plans?: readonly string[];
  readonly enabled?: boolean;
}

export type AiModerationStage = "input" | "output" | "tool";
export type AiModerationAction = "allow" | "flag" | "redact" | "block";

export interface AiModerationEvent {
  readonly id: string;
  readonly organizationId: string;
  readonly chatId: string | undefined;
  readonly messageId: string | undefined;
  readonly userId: string | undefined;
  readonly stage: AiModerationStage;
  /** What the moderator flagged, such as `pii` or `prompt-injection`. */
  readonly category: string;
  readonly score: number | undefined;
  readonly action: AiModerationAction;
  readonly createdAt: Temporal.Instant;
}

export interface AiModerationInput {
  readonly organizationId: string;
  readonly stage: AiModerationStage;
  readonly action: AiModerationAction;
  readonly category: string;
  readonly chatId?: string;
  readonly messageId?: string;
  readonly userId?: string;
  readonly score?: number;
}

export interface AiChatOptions extends BlockTemporalOptions {
  /** Calls as the user: `rpcTransport(supabase)` or `sqlTransport(postgres.asUser(claims))`. */
  readonly transport: BlockTransport;
  /**
   * Calls as the service role, for what only the server writes (assistant
   * messages, stream claims, approvals, the model catalog). Defaults to
   * `transport`, which then has to be a service transport.
   */
  readonly service?: BlockTransport;
  /** The module schema (`sql.modules["ai-chat"].schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

export interface AiChat {
  readonly chats: {
    create(
      organizationId: string,
      input?: AiChatInput,
    ): AsyncResult<AiChatRecord>;
    get(chatId: string): AsyncResult<AiChatRecord>;
    list(query?: AiChatQuery): AsyncResult<AiChatPage>;
    update(chatId: string, patch: AiChatPatch): AsyncResult<AiChatRecord>;
    remove(chatId: string): AsyncResult<boolean>;
    /** Deletes expired temporary chats (service role); returns how many. */
    purge(batch?: number): AsyncResult<number>;
  };
  readonly projects: {
    create(
      organizationId: string,
      input: AiProjectInput & { readonly name: string },
    ): AsyncResult<AiProject>;
    update(projectId: string, input: AiProjectInput): AsyncResult<AiProject>;
    list(organizationId: string): AsyncResult<readonly AiProject[]>;
    remove(projectId: string): AsyncResult<boolean>;
  };
  readonly messages: {
    /**
     * Stores the user's message under the chat's leaf. A retry with the same
     * id is a no-op; the same id with other parts is an edit, stored as a
     * sibling with a fresh id.
     */
    appendUser(
      chatId: string,
      message: AiMessage,
      options?: {
        readonly trigger?: AiUserMessageTrigger;
        readonly messageId?: string;
      },
    ): AsyncResult<AiAppendResult>;
    /** Stores an answer (service role); a retry with the same id updates it. */
    saveAssistant(
      chatId: string,
      message: AiMessage,
      options: AiAssistantMessageOptions,
    ): AsyncResult<AiSaveResult>;
    /** The messages from the root to `leafId`, default the chat's leaf. */
    path(
      chatId: string,
      options?: { readonly leafId?: string; readonly native?: boolean },
    ): AsyncResult<readonly AiStoredMessage[]>;
    siblings(
      chatId: string,
      messageId: string,
    ): AsyncResult<readonly AiMessageSibling[]>;
    /** Shows the branch through `messageId`; returns the new leaf. */
    switchBranch(chatId: string, messageId: string): AsyncResult<string>;
  };
  readonly runs: {
    /** Claims the chat's answer for one stream (service role). */
    claim(
      chatId: string,
      streamId: string,
      options?: {
        readonly model?: string;
        readonly messageId?: string;
        readonly engine?: string;
        /** The durable engine's own run id, such as a Workflow SDK run. */
        readonly externalRunId?: string;
      },
    ): AsyncResult<AiStreamClaim>;
    release(
      chatId: string,
      streamId: string,
      options?: AiRunRelease,
    ): AsyncResult<boolean>;
    /** Asks the running answer to stop; `undefined` when none runs. */
    stop(
      chatId: string,
    ): AsyncResult<
      { readonly streamId: string; readonly runId: string } | undefined
    >;
    /** Writes the gateway's cost for a generation, once it is known. */
    setCost(
      generationId: string,
      costMicroUsd: number,
      usage?: Readonly<Record<string, unknown>>,
    ): AsyncResult<boolean>;
  };
  readonly approvals: {
    request(
      chatId: string,
      request: AiToolApprovalRequest,
    ): AsyncResult<AiToolApproval>;
    decide(
      approvalId: string,
      approved: boolean,
      reason?: string,
    ): AsyncResult<AiToolApproval>;
    list(
      chatId: string,
      approvalIds?: readonly string[],
    ): AsyncResult<readonly AiToolApproval[]>;
    /** Sets a tool's policy for a tenant (`ai_chat.admin`); `null` removes it. */
    setPolicy(
      organizationId: string,
      tool: string,
      policy: AiToolPolicy | null,
    ): AsyncResult<AiToolPolicy | undefined>;
    policies(
      organizationId: string,
    ): AsyncResult<Readonly<Record<string, AiToolPolicy>>>;
  };
  readonly inputs: {
    open(
      chatId: string,
      request: AiPendingInputRequest,
    ): AsyncResult<AiPendingInput>;
    answer(inputId: string, answer: unknown): AsyncResult<AiPendingInput>;
  };
  readonly feedback: {
    rate(
      chatId: string,
      messageId: string,
      rating: -1 | 0 | 1,
      options?: { readonly reason?: string; readonly comment?: string },
    ): AsyncResult<AiFeedback>;
  };
  readonly shares: {
    create(chatId: string, leafId?: string): AsyncResult<AiShareLink>;
    revoke(shareId: string): AsyncResult<boolean>;
    list(chatId: string): AsyncResult<readonly AiChatShare[]>;
    /** Reads a shared chat by its token; anyone with the token may. */
    get(token: string): AsyncResult<SharedAiChat>;
  };
  readonly models: {
    /** The enabled models the tenant's plans allow. */
    allowed(organizationId?: string | null): AsyncResult<readonly AiModel[]>;
    /** Upserts the catalog (service role); `prune` deletes the rest. */
    upsert(
      models: readonly AiModelInput[],
      options?: { readonly prune?: boolean },
    ): AsyncResult<number>;
  };
  readonly moderation: {
    record(event: AiModerationInput): AsyncResult<AiModerationEvent>;
    list(
      organizationId: string,
      size?: number,
    ): AsyncResult<readonly AiModerationEvent[]>;
  };
}

/** The topic of one chat's events (`message.saved`, `stream.started`, ...). */
export function aiChatTopic(chatId: string, prefix = "ai-chat"): string {
  return `${prefix}:${chatId}`;
}

/** The topic that tells a user their chat list changed. */
export function aiChatListTopic(userId: string, prefix = "ai-chats"): string {
  return `${prefix}:${userId}`;
}

export function createAiChat(options: AiChatOptions): AiChat {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );
  const isTrue = (value: unknown): boolean => value === true;
  const count = (value: unknown): number =>
    typeof value === "number" ? value : Number(value ?? 0);

  return {
    chats: {
      create: (organizationId, input = {}) =>
        (input.ownerId === undefined ? call : service)(
          "create_ai_chat",
          { tenant: organizationId, fields: chatFields(input) },
          chatOf,
        ),
      get: (chatId) => call("get_ai_chat", { chat: chatId }, chatOf),
      list: (query = {}) =>
        call(
          "list_ai_chats",
          {
            tenant: query.organizationId ?? null,
            search: query.search,
            project: query.projectId,
            pinned: query.pinned,
            archived: query.archived,
            after: query.after,
            size: query.size,
          },
          (value) => {
            const row = recordOf(value, "list_ai_chats");
            return {
              items: recordsOf(row["items"], "list_ai_chats").map(chatOf),
              next: optionalText(row["next"]),
            };
          },
        ),
      update: (chatId, patch) =>
        call(
          "update_ai_chat",
          { chat: chatId, fields: patchFields(patch) },
          chatOf,
        ),
      remove: (chatId) => call("delete_ai_chat", { chat: chatId }, isTrue),
      purge: (batch) => service("purge_ai_chats", { batch }, count),
    },
    projects: {
      create: (organizationId, input) =>
        call(
          "save_ai_project",
          { id: null, tenant: organizationId, fields: projectFields(input) },
          projectOf,
        ),
      update: (projectId, input) =>
        call(
          "save_ai_project",
          { id: projectId, tenant: null, fields: projectFields(input) },
          projectOf,
        ),
      list: (organizationId) =>
        call("list_ai_projects", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_ai_projects").map(projectOf),
        ),
      remove: (projectId) =>
        call("delete_ai_project", { id: projectId }, isTrue),
    },
    messages: {
      appendUser: (chatId, message, appendOptions = {}) =>
        call(
          "append_ai_user_message",
          {
            chat: chatId,
            message: canonical(message),
            trigger: appendOptions.trigger,
            message_id: appendOptions.messageId,
          },
          savedOf,
        ),
      saveAssistant: (chatId, message, saveOptions) =>
        service(
          "save_ai_assistant_message",
          {
            chat: chatId,
            message: canonical(message),
            parent_id: saveOptions.parentId,
            status: saveOptions.status,
            model: saveOptions.model,
            format: saveOptions.format,
            native:
              saveOptions.native === undefined
                ? undefined
                : { value: saveOptions.native },
            run: saveOptions.runId,
          },
          savedOf,
        ),
      path: (chatId, pathOptions = {}) =>
        call(
          "ai_message_path",
          {
            chat: chatId,
            leaf: pathOptions.leafId,
            include_native: pathOptions.native,
          },
          (value) =>
            recordsOf(value, "ai_message_path").map((row) => {
              const stored = storedOf(row);
              const native = stored.native;
              return isRecord(native) && "value" in native
                ? { ...stored, native: native["value"] }
                : stored;
            }),
        ),
      siblings: (chatId, messageId) =>
        call(
          "ai_message_siblings",
          { chat: chatId, message_id: messageId },
          (value) =>
            recordsOf(value, "ai_message_siblings").map((row) => ({
              id: textOf(row["id"]),
              role: oneOf(row["role"], ROLES, "user"),
              createdAt: instant(row["created_at"]),
            })),
        ),
      switchBranch: (chatId, messageId) =>
        call(
          "switch_ai_branch",
          { chat: chatId, message_id: messageId },
          (value) => textOf(recordOf(value, "switch_ai_branch")["leaf_id"]),
        ),
    },
    runs: {
      claim: (chatId, streamId, claimOptions = {}) =>
        service(
          "claim_ai_chat_stream",
          {
            chat: chatId,
            stream: streamId,
            model: claimOptions.model,
            message_id: claimOptions.messageId,
            engine: claimOptions.engine,
            external_run_id: claimOptions.externalRunId,
          },
          (value) => {
            const row = recordOf(value, "claim_ai_chat_stream");
            return {
              claimed: row["claimed"] === true,
              streamId: optionalText(row["stream_id"]),
              runId: optionalText(row["run_id"]),
            };
          },
        ),
      release: (chatId, streamId, release = {}) =>
        service(
          "release_ai_chat_stream",
          {
            chat: chatId,
            stream: streamId,
            status: release.status,
            usage: release.usage,
            generation_id: release.generationId,
            error: release.error,
            cost_micro_usd: release.costMicroUsd,
          },
          isTrue,
        ),
      stop: (chatId) =>
        call("request_ai_chat_stop", { chat: chatId }, (value) => {
          const row = record(value);
          const streamId = optionalText(row["stream_id"]);
          const runId = optionalText(row["run_id"]);
          return streamId && runId ? { streamId, runId } : undefined;
        }),
      setCost: (generationId, costMicroUsd, usage) =>
        service(
          "set_ai_run_cost",
          {
            generation_id: generationId,
            cost_micro_usd: costMicroUsd,
            usage,
          },
          isTrue,
        ),
    },
    approvals: {
      request: (chatId, request) =>
        service(
          "record_ai_tool_approval",
          {
            chat: chatId,
            approval: {
              approval_id: request.approvalId,
              tool: request.tool,
              tool_call_id: request.toolCallId,
              input: request.input ?? null,
              run_id: request.runId ?? null,
              message_id: request.messageId ?? null,
              signature: request.signature ?? null,
            },
          },
          approvalOf,
        ),
      decide: (approvalId, approved, reason) =>
        call(
          "decide_ai_tool_approval",
          { approval_id: approvalId, approved, reason },
          approvalOf,
        ),
      list: (chatId, approvalIds) =>
        call(
          "get_ai_tool_approvals",
          { chat: chatId, ids: approvalIds },
          (value) => recordsOf(value, "get_ai_tool_approvals").map(approvalOf),
        ),
      setPolicy: (organizationId, tool, policy) =>
        call(
          "set_ai_tool_policy",
          { tenant: organizationId, tool, policy },
          (value) => policyOf(record(value)["policy"]),
        ),
      policies: (organizationId) =>
        call("ai_tool_policies_for", { tenant: organizationId }, (value) => {
          const policies: Record<string, AiToolPolicy> = {};
          for (const [tool, policy] of Object.entries(record(value))) {
            const known = policyOf(policy);
            if (known) policies[tool] = known;
          }
          return policies;
        }),
    },
    inputs: {
      open: (chatId, request) =>
        service(
          "open_ai_pending_input",
          {
            chat: chatId,
            input: {
              question: request.question,
              schema: request.schema ?? null,
              run_id: request.runId ?? null,
              tool_call_id: request.toolCallId ?? null,
            },
          },
          inputOf,
        ),
      answer: (inputId, answer) =>
        call(
          "answer_ai_pending_input",
          { id: inputId, answer: { value: answer } },
          inputOf,
        ),
    },
    feedback: {
      rate: (chatId, messageId, rating, rateOptions = {}) =>
        call(
          "rate_ai_message",
          {
            chat: chatId,
            message_id: messageId,
            rating: rating === 0 ? null : rating,
            reason: rateOptions.reason,
            comment: rateOptions.comment,
          },
          (value) =>
            value === null || value === undefined
              ? {
                  chatId,
                  messageId,
                  rating: 0,
                  reason: undefined,
                  comment: undefined,
                }
              : feedbackOf(value),
        ),
    },
    shares: {
      create: (chatId, leafId) =>
        call("share_ai_chat", { chat: chatId, leaf: leafId }, (value) => {
          const row = recordOf(value, "share_ai_chat");
          return {
            id: textOf(row["id"]),
            token: textOf(row["token"]),
            leafId: textOf(row["leaf_id"]),
            createdAt: instant(row["created_at"]),
          };
        }),
      revoke: (shareId) =>
        call("revoke_ai_chat_share", { id: shareId }, isTrue),
      list: (chatId) =>
        call("list_ai_chat_shares", { chat: chatId }, (value) =>
          recordsOf(value, "list_ai_chat_shares").map(shareOf),
        ),
      get: (token) => call("get_shared_ai_chat", { token }, sharedOf),
    },
    models: {
      allowed: (organizationId) =>
        call("allowed_ai_models", { tenant: organizationId ?? null }, (value) =>
          recordsOf(value, "allowed_ai_models").map(modelOf),
        ),
      upsert: (models, upsertOptions = {}) =>
        service(
          "upsert_ai_models",
          { models: { models }, prune: upsertOptions.prune },
          count,
        ),
    },
    moderation: {
      record: (event) =>
        service(
          "record_ai_moderation_event",
          {
            event: {
              organization_id: event.organizationId,
              stage: event.stage,
              action: event.action,
              chat_id: event.chatId ?? null,
              message_id: event.messageId ?? null,
              user_id: event.userId ?? null,
              category: event.category,
              score: event.score ?? null,
            },
          },
          moderationOf,
        ),
      list: (organizationId, size) =>
        call(
          "list_ai_moderation_events",
          { tenant: organizationId, size },
          (value) =>
            recordsOf(value, "list_ai_moderation_events").map(moderationOf),
        ),
    },
  };
}
