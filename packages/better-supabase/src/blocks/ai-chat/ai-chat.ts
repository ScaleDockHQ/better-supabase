import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { BlockTemporalOptions } from "../shared.ts";
import type { AiRuns } from "./durable.ts";
import type { AiMessage } from "./message.ts";
import type {
  AiChatMessageStorage,
  AiChatRecord,
  AiChatInput,
  AiChatPatch,
  AiChatQuery,
  AiChatPage,
  AiProject,
  AiProjectInput,
  AiStoredMessage,
  AiMessageSibling,
  AiAppendResult,
  AiAssistantMessageOptions,
  AiSaveResult,
  AiStreamClaim,
  AiRunRelease,
  AiToolApproval,
  AiToolApprovalRequest,
  AiToolPolicy,
  AiPendingInput,
  AiPendingInputRequest,
  AiFeedback,
  AiChatShare,
  AiShareLink,
  SharedAiChat,
  AiModel,
  AiModelInput,
  AiModerationEvent,
  AiModerationInput,
  AiChatParticipantRole,
  AiChatParticipant,
  AiUserMessageOptions,
} from "./records.ts";
import type { AiSandboxes } from "./sandboxes.ts";

import {
  allWithFields,
  blockFields,
  extraOf,
  withFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import {
  applyTemporal,
  blockCall,
  isRecord,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
  oneOf,
  pageOf,
  instantOf,
} from "../shared.ts";
import { aiRunLookups } from "./durable.ts";
import {
  approvalOf,
  record,
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
  nativeMessage,
  participantOf,
} from "./rows.ts";
import { aiSandboxes } from "./sandboxes.ts";

export type {
  AiChatMessageStorage,
  AiChatVisibility,
  AiChatRecord,
  AiChatInput,
  AiChatPatch,
  AiChatQuery,
  AiChatPage,
  AiProject,
  AiProjectInput,
  AiStoredMessageStatus,
  AiStoredMessage,
  AiMessageSibling,
  AiUserMessageTrigger,
  AiAppendResult,
  AiAssistantMessageOptions,
  AiSaveResult,
  AiStreamClaim,
  AiRunStatus,
  AiRunRelease,
  AiApprovalDecision,
  AiToolApproval,
  AiToolApprovalRequest,
  AiToolPolicy,
  AiPendingInput,
  AiPendingInputRequest,
  AiFeedback,
  AiChatShare,
  AiShareLink,
  SharedAiChat,
  AiModel,
  AiModelInput,
  AiModerationStage,
  AiModerationAction,
  AiModerationEvent,
  AiModerationInput,
  AiChatParticipantRole,
  AiChatParticipant,
  AiUserMessageOptions,
} from "./records.ts";

export interface AiChatOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the chat columns the app adds
   * (`blocks.ai-chat.options.extraColumns`), keyed by column name. It types and
   * parses them on the chat reads, and validates them on `chats.create` and
   * `chats.update`, which return a `validation` error for a bad value.
   */
  readonly fields?: S;
  /**
   * The message shape `blocks.ai-chat.options.messages` installs, which
   * `defineBlocks` passes from `blocks.generated.ts`. With `parts: "native"`
   * the client stores the SDK's own message (the `native` of `appendUser` and
   * `saveAssistant`) in place of the canonical one.
   */
  readonly messages?: AiChatMessageStorage;
  /** `withBlockHooks` hooks around the client's methods. */
  readonly hooks?: NoInfer<BlockHooks<AiChat<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
  /**
   * Calls as the user: `rpcTransport(supabase)` or
   * `sqlTransport(postgres.asUser(claims))`.
   */
  readonly transport: BlockTransport;
  /**
   * Calls as the service role, for what only the server writes (assistant
   * messages, stream claims, approvals, the model catalog). Defaults to
   * `transport`, which then has to be a service transport.
   */
  readonly service?: BlockTransport;
  /** The module schema (`blocks["ai-chat"].schema`), default `better_supabase`. */
  readonly schema?: string;
  readonly mappers?: readonly ErrorMapper[];
}

/** `F` is the extra chat fields `options.fields` describes. */
export interface AiChat<F extends object = Record<never, never>> {
  readonly chats: {
    /**
     * Keys besides the input's own are the chat's extra columns. `null` makes a
     * chat outside a tenant, with `options.tenant: false`.
     */
    create(
      organizationId: string | null,
      input?: AiChatInput & Partial<F>,
    ): AsyncResult<AiChatRecord & F>;
    get(chatId: string): AsyncResult<AiChatRecord & F>;
    list(query?: AiChatQuery): AsyncResult<AiChatPage<F>>;
    update(
      chatId: string,
      patch: AiChatPatch & Partial<F>,
    ): AsyncResult<AiChatRecord & F>;
    remove(chatId: string): AsyncResult<boolean>;
    /** Deletes expired temporary chats (service role); returns how many. */
    purge(batch?: number): AsyncResult<number>;
  };
  readonly projects: {
    /**
     * `null` makes a project outside a tenant. Keys of `fields` are the project
     * table's extra columns.
     */
    create(
      organizationId: string | null,
      input: AiProjectInput & { readonly name: string },
      fields?: Readonly<Record<string, unknown>>,
    ): AsyncResult<AiProject>;
    update(
      projectId: string,
      input: AiProjectInput,
      fields?: Readonly<Record<string, unknown>>,
    ): AsyncResult<AiProject>;
    list(organizationId: string | null): AsyncResult<readonly AiProject[]>;
    remove(projectId: string): AsyncResult<boolean>;
  };
  /** The people besides the owner who take part in a chat. */
  readonly participants: {
    /** Adds someone, or changes their role (the owner, or the service role). */
    add(
      chatId: string,
      userId: string,
      options?: {
        readonly role?: AiChatParticipantRole;
        readonly fields?: Readonly<Record<string, unknown>>;
      },
    ): AsyncResult<AiChatParticipant>;
    /** The owner removes anyone; a participant removes themselves. */
    remove(chatId: string, userId: string): AsyncResult<boolean>;
    list(chatId: string): AsyncResult<readonly AiChatParticipant[]>;
  };
  readonly messages: {
    /**
     * Stores the user's message under the chat's leaf. A retry with the same id
     * is a no-op. In a tree the same id with other parts is an edit, stored as
     * a sibling with a fresh id; in a linear list it replaces the message and
     * deletes the ones after it.
     */
    appendUser(
      chatId: string,
      message: AiMessage,
      options?: AiUserMessageOptions,
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
    /**
     * Shows the branch through `messageId`; returns the new leaf. A linear list
     * has no branches and answers `AI_CHAT_LINEAR`.
     */
    switchBranch(chatId: string, messageId: string): AsyncResult<string>;
  };
  /**
   * The sandboxes chats and harness sessions started, with one idle-stop claim
   * for both (service role, except `list`).
   */
  readonly sandboxes: AiSandboxes;
  /** Runs: the stream claim, lookups, steps and the approval inbox. */
  readonly runs: AiRuns & {
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
    /** Sets a tool's policy for a tenant (`ai_chat.manage`); `null` removes it. */
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
    /** Keys of `fields` are the moderation table's extra columns. */
    record(
      event: AiModerationInput,
      fields?: Readonly<Record<string, unknown>>,
    ): AsyncResult<AiModerationEvent>;
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

const CHAT_INPUT: ReadonlySet<string> = new Set([
  "id",
  "title",
  "model",
  "projectId",
  "agentId",
  "visibility",
  "pinned",
  "temporary",
  "ownerId",
  "archived",
]);

export function createAiChat<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: AiChatOptions<S>): AiChat<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const fields: BlockFields<F> = blockFields(options.fields, "chat fields");

  const typed = (value: unknown): AsyncResult<AiChatRecord & F> =>
    AsyncResult.from(() => withFields(fields, value, chatOf(value)));

  const checked = (input: object): AsyncResult<Record<string, unknown>> =>
    AsyncResult.from(() => fields.write(extraOf(input, CHAT_INPUT)));

  const call = blockCall(options.transport, options.schema, options.mappers);

  const service = blockCall(
    options.service ?? options.transport,
    options.schema,
    options.mappers,
  );

  const isTrue = (value: unknown): boolean => value === true;

  const native = options.messages?.parts === "native";

  const messageOf = (
    message: AiMessage,
    raw: unknown,
    fields: Readonly<Record<string, unknown>> | undefined,
  ): Record<string, unknown> => ({
    ...(native && raw !== undefined ? nativeMessage(raw) : canonical(message)),
    ...(fields === undefined ? {} : { fields }),
  });

  const count = (value: unknown): number =>
    typeof value === "number" ? value : Number(value ?? 0);

  const client: AiChat<F> = {
    chats: {
      create: (organizationId, input = {}) =>
        checked(input).andThen((extra) =>
          (input.ownerId === undefined ? call : service)(
            "create_ai_chat",
            {
              tenant: organizationId,
              fields: { ...extra, ...chatFields(input) },
            },
            (value) => value,
          ).andThen(typed),
        ),
      get: (chatId) =>
        call("get_ai_chat", { chat: chatId }, (value) => value).andThen(typed),
      list: (query = {}) =>
        call(
          "list_ai_chats",
          {
            tenant: query.organizationId ?? null,
            search: query.search,
            project: query.projectId,
            pinned: query.pinned,
            archived: query.archived,
            after: pageOf(query).cursor,
            size: pageOf(query).limit,
          },
          (value) => {
            const row = recordOf(value, "list_ai_chats");

            return {
              items: recordsOf(row["items"], "list_ai_chats").map(
                (item) => [item, chatOf(item)] as const,
              ),
              next: optionalText(row["next"]),
            };
          },
        ).andThen(async ({ items, next }) => {
          const parsed = await allWithFields(fields, items);

          return parsed.ok ? ok({ items: parsed.data, next }) : parsed;
        }),
      update: (chatId, patch) =>
        checked(patch).andThen((extra) =>
          call(
            "update_ai_chat",
            { chat: chatId, fields: { ...extra, ...patchFields(patch) } },
            (value) => value,
          ).andThen(typed),
        ),
      remove: (chatId) => call("delete_ai_chat", { chat: chatId }, isTrue),
      purge: (batch) => service("purge_ai_chats", { batch }, count),
    },
    projects: {
      create: (organizationId, input, extra = {}) =>
        call(
          "save_ai_project",
          {
            id: null,
            tenant: organizationId,
            fields: { ...extra, ...projectFields(input) },
          },
          projectOf,
        ),
      update: (projectId, input, extra = {}) =>
        call(
          "save_ai_project",
          {
            id: projectId,
            tenant: null,
            fields: { ...extra, ...projectFields(input) },
          },
          projectOf,
        ),
      list: (organizationId) =>
        call("list_ai_projects", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_ai_projects").map(projectOf),
        ),
      remove: (projectId) =>
        call("delete_ai_project", { id: projectId }, isTrue),
    },
    participants: {
      add: (chatId, userId, addOptions = {}) =>
        call(
          "add_ai_chat_participant",
          {
            chat: chatId,
            participant: userId,
            participant_role: addOptions.role,
            fields: addOptions.fields,
          },
          participantOf,
        ),
      remove: (chatId, userId) =>
        call(
          "remove_ai_chat_participant",
          { chat: chatId, participant: userId },
          isTrue,
        ),
      list: (chatId) =>
        call("list_ai_chat_participants", { chat: chatId }, (value) =>
          recordsOf(value, "list_ai_chat_participants").map(participantOf),
        ),
    },
    messages: {
      appendUser: (chatId, message, appendOptions = {}) =>
        call(
          "append_ai_user_message",
          {
            chat: chatId,
            message: messageOf(
              message,
              appendOptions.native,
              appendOptions.fields,
            ),
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
            message: messageOf(message, saveOptions.native, saveOptions.fields),
            parent_id: saveOptions.parentId,
            status: saveOptions.status,
            model: saveOptions.model,
            ...(native && saveOptions.native !== undefined
              ? { format: "native" }
              : {
                  format: saveOptions.format,
                  native:
                    saveOptions.native === undefined
                      ? undefined
                      : { value: saveOptions.native },
                }),
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
              createdAt: instantOf(row["created_at"]),
            })),
        ),
      switchBranch: (chatId, messageId) =>
        call(
          "switch_ai_branch",
          { chat: chatId, message_id: messageId },
          (value) => textOf(recordOf(value, "switch_ai_branch")["leaf_id"]),
        ),
    },
    sandboxes: aiSandboxes(call, service),
    runs: {
      ...aiRunLookups(options),
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
          { generation_id: generationId, cost_micro_usd: costMicroUsd, usage },
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

            if (known) {
              policies[tool] = known;
            }
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
            createdAt: instantOf(row["created_at"]),
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
      record: (event, extra) =>
        service(
          "record_ai_moderation_event",
          {
            event: {
              ...(extra === undefined ? {} : { fields: extra }),
              organization_id: event.organizationId ?? null,
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

  return withBlockHooks(client, options.hooks, {
    block: "ai-chat",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
