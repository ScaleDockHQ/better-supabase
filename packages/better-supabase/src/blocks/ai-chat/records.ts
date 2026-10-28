import type { FinalRunState } from "../../core/run-state.ts";
import type { AiRunState } from "./durable.ts";
import type { AiMessage, AiMessageRole } from "./message.ts";

export type AiChatVisibility = "private" | "organization";

export interface AiChatRecord {
  readonly id: string;
  /** `undefined` for a chat outside a tenant (`options.tenant: false`). */
  readonly organizationId: string | undefined;
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
  readonly cursor?: string;
  readonly limit?: number;
}

export interface AiChatPage<F extends object = Record<never, never>> {
  readonly items: readonly (AiChatRecord & F)[];
  /** Pass as `after` for the next page; `undefined` on the last one. */
  readonly next: string | undefined;
}

export interface AiProject {
  readonly id: string;
  readonly organizationId: string | undefined;
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
  /** The message before it: its parent in a tree, the one before in a list. */
  readonly parentId: string | undefined;
  /** The user who wrote it; `undefined` for an answer. */
  readonly authorId: string | undefined;
  /**
   * `canonical`, the format `native` holds (such as `ai-sdk-ui`), or `native`
   * when the row's own parts are the SDK's (`options.messages.parts`).
   */
  readonly format: string;
  /**
   * The SDK's own message: the stored copy when `path(..., { native: true })`
   * asks for it, or the row itself when `format` is `native`.
   */
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
  /** Values for the message table's extra columns, keyed by column name. */
  readonly fields?: Readonly<Record<string, unknown>>;
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

/** How a run ended, as `runs.release` records it. */
export type AiRunStatus = Extract<AiRunState, FinalRunState>;

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
  /**
   * A signature over the input, so the decision can't be replayed on other
   * input.
   */
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
  readonly organizationId: string | undefined;
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
  /** Leave it out for a chat outside a tenant. */
  readonly organizationId?: string | undefined;
  readonly stage: AiModerationStage;
  readonly action: AiModerationAction;
  readonly category: string;
  readonly chatId?: string;
  readonly messageId?: string;
  readonly userId?: string;
  readonly score?: number;
}

/** Who besides the owner takes part in a chat. */
export type AiChatParticipantRole = "viewer" | "editor";

/**
 * A participant: a viewer reads the chat, an editor also sends messages, stops
 * an answer and switches branches.
 */
export interface AiChatParticipant {
  readonly chatId: string;
  readonly userId: string;
  readonly role: AiChatParticipantRole;
  readonly addedBy: string | undefined;
  readonly createdAt: Temporal.Instant | undefined;
  /** The participant table's extra columns. */
  readonly fields: Readonly<Record<string, unknown>>;
}

export interface AiUserMessageOptions {
  readonly trigger?: AiUserMessageTrigger;
  readonly messageId?: string;
  /**
   * The SDK's own message (such as a `UIMessage`). With `messages: { parts:
   * "native" }` it is stored instead of `message`.
   */
  readonly native?: unknown;
  /** Values for the message table's extra columns, keyed by column name. */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/** `blocks.ai-chat.options.messages`: how the message table is keyed and shaped. */
export interface AiChatMessageStorage {
  /**
   * `uuid` keys messages by uuid; client ids must then be uuids. Default
   * `text`.
   */
  readonly key?: "text" | "uuid";
  /**
   * `false` keeps one linear list per chat. Default: a tree when `parent_id`
   * exists.
   */
  readonly tree?: boolean;
  /** `native` stores the SDK's own parts. Default `canonical`. */
  readonly parts?: "canonical" | "native";
}
