import type {
  AiChatInput,
  AiChatPatch,
  AiChatRecord,
  AiChatShare,
  AiFeedback,
  AiModel,
  AiModerationEvent,
  AiPendingInput,
  AiProject,
  AiProjectInput,
  AiSaveResult,
  AiStoredMessage,
  AiToolApproval,
  AiToolPolicy,
  SharedAiChat,
} from "./ai-chat.ts";
import type { AiMessage, AiMessagePart, AiMessageRole } from "./message.ts";

import {
  isRecord,
  oneOf,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  stringsOf,
  textOf,
  toInstant,
} from "../shared.ts";
import { AI_MESSAGE_PART_TYPES } from "./message.ts";

export const record = (value: unknown): Readonly<Record<string, unknown>> =>
  isRecord(value) ? value : {};

export const instant = (value: unknown): Temporal.Instant =>
  toInstant(textOf(value));

const optionalNumber = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

export function chatOf(value: unknown): AiChatRecord {
  const row = recordOf(value, "ai_chat");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: textOf(row["owner_id"]),
    projectId: optionalText(row["project_id"]),
    agentId: optionalText(row["agent_id"]),
    title: textOf(row["title"] ?? ""),
    model: optionalText(row["model"]),
    visibility: oneOf(
      row["visibility"],
      ["private", "organization"],
      "private",
    ),
    pinned: row["pinned"] === true,
    archivedAt: optionalInstant(row["archived_at"]),
    temporary: row["is_temporary"] === true,
    expiresAt: optionalInstant(row["expires_at"]),
    leafId: optionalText(row["current_leaf_id"]),
    activeStreamId: optionalText(row["active_stream_id"]),
    activeRunId: optionalText(row["active_run_id"]),
    lastMessageAt: instant(row["last_message_at"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

export function projectOf(value: unknown): AiProject {
  const row = recordOf(value, "ai_project");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    ownerId: textOf(row["owner_id"]),
    name: textOf(row["name"]),
    instructions: textOf(row["instructions"] ?? ""),
    defaultModel: optionalText(row["default_model"]),
    pinned: row["pinned"] === true,
    archivedAt: optionalInstant(row["archived_at"]),
    createdAt: instant(row["created_at"]),
    updatedAt: instant(row["updated_at"]),
  };
}

const PART_TYPES: ReadonlySet<unknown> = new Set(AI_MESSAGE_PART_TYPES);

/** The table's check constraint admits only canonical parts; this keeps the type honest. */
function isPart(value: unknown): value is AiMessagePart {
  return isRecord(value) && PART_TYPES.has(value["type"]);
}

export const ROLES: readonly AiMessageRole[] = [
  "system",
  "user",
  "assistant",
  "tool",
];

export function storedOf(value: unknown): AiStoredMessage {
  const row = recordOf(value, "ai_message_path");
  const metadata = row["metadata"];
  const parts: readonly AiMessagePart[] = Array.isArray(row["parts"])
    ? row["parts"].filter(isPart)
    : [];
  return {
    id: textOf(row["id"]),
    role: oneOf(row["role"], ROLES, "user"),
    parts,
    ...(isRecord(metadata) && Object.keys(metadata).length > 0
      ? { metadata }
      : {}),
    parentId: optionalText(row["parent_id"]),
    format: textOf(row["format"] ?? "canonical"),
    native: row["native"] ?? undefined,
    model: optionalText(row["model"]),
    status: oneOf(row["status"], ["complete", "aborted", "error"], "complete"),
    createdAt: instant(row["created_at"]),
    siblingCount: optionalNumber(row["sibling_count"]) ?? 1,
    siblingIndex: optionalNumber(row["sibling_index"]) ?? 0,
  };
}

export function savedOf(value: unknown): AiSaveResult {
  const row = recordOf(value, "ai_message");
  return {
    messageId: textOf(row["message_id"]),
    parentId: optionalText(row["parent_id"]),
    created: row["created"] === true,
  };
}

/** Reads an approval row from the module's JSON. */
export function approvalOf(value: unknown): AiToolApproval {
  const row = recordOf(value, "ai_tool_approval");
  return {
    approvalId: textOf(row["approval_id"]),
    chatId: textOf(row["chat_id"]),
    runId: optionalText(row["run_id"]),
    messageId: optionalText(row["message_id"]),
    tool: textOf(row["tool"]),
    toolCallId: textOf(row["tool_call_id"]),
    input: row["input"] ?? undefined,
    decision: oneOf(
      row["decision"],
      ["pending", "approved", "denied"],
      "pending",
    ),
    reason: optionalText(row["reason"]),
    signature: optionalText(row["signature"]),
    decidedBy: optionalText(row["decided_by"]),
    decidedAt: optionalInstant(row["decided_at"]),
    createdAt: instant(row["created_at"]),
  };
}

const POLICIES: readonly AiToolPolicy[] = ["auto", "ask", "deny"];

export function policyOf(value: unknown): AiToolPolicy | undefined {
  return POLICIES.find((policy) => policy === value);
}

export function inputOf(value: unknown): AiPendingInput {
  const row = recordOf(value, "ai_pending_input");
  const answer = row["answer"];
  return {
    id: textOf(row["id"]),
    chatId: textOf(row["chat_id"]),
    runId: optionalText(row["run_id"]),
    toolCallId: optionalText(row["tool_call_id"]),
    question: textOf(row["question"] ?? ""),
    schema: row["schema"] ?? undefined,
    answer: isRecord(answer) && "value" in answer ? answer["value"] : answer,
    answeredAt: optionalInstant(row["answered_at"]),
    createdAt: instant(row["created_at"]),
  };
}

export function feedbackOf(value: unknown): AiFeedback {
  const row = recordOf(value, "rate_ai_message");
  const rating = row["rating"];
  return {
    chatId: textOf(row["chat_id"]),
    messageId: textOf(row["message_id"]),
    rating: rating === 1 || rating === -1 ? rating : 0,
    reason: optionalText(row["reason"]),
    comment: optionalText(row["comment"]),
  };
}

export function shareOf(value: unknown): AiChatShare {
  const row = recordOf(value, "list_ai_chat_shares");
  return {
    id: textOf(row["id"]),
    leafId: textOf(row["leaf_id"]),
    createdBy: optionalText(row["created_by"]),
    createdAt: instant(row["created_at"]),
    revokedAt: optionalInstant(row["revoked_at"]),
  };
}

export function sharedOf(value: unknown): SharedAiChat {
  const row = recordOf(value, "get_shared_ai_chat");
  const chat = record(row["chat"]);
  return {
    chat: {
      id: textOf(chat["id"]),
      title: textOf(chat["title"] ?? ""),
      model: optionalText(chat["model"]),
      createdAt: instant(chat["created_at"]),
    },
    leafId: textOf(row["leaf_id"]),
    messages: recordsOf(row["messages"], "get_shared_ai_chat").map(storedOf),
  };
}

export function modelOf(value: unknown): AiModel {
  const row = recordOf(value, "allowed_ai_models");
  return {
    id: textOf(row["model_id"]),
    provider: textOf(row["provider"]),
    name: textOf(row["name"]),
    pricing: record(row["pricing"]),
    capabilities: record(row["capabilities"]),
    plans: stringsOf(row["plans"]),
    enabled: row["enabled"] !== false,
    refreshedAt: optionalInstant(row["refreshed_at"]),
  };
}

export function moderationOf(value: unknown): AiModerationEvent {
  const row = recordOf(value, "ai_moderation_event");
  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organization_id"]),
    chatId: optionalText(row["chat_id"]),
    messageId: optionalText(row["message_id"]),
    userId: optionalText(row["user_id"]),
    stage: oneOf(row["stage"], ["input", "output", "tool"], "input"),
    category: textOf(row["category"] ?? ""),
    score: optionalNumber(row["score"]),
    action: oneOf(row["action"], ["allow", "flag", "redact", "block"], "flag"),
    createdAt: instant(row["created_at"]),
  };
}

/** The fields `create_ai_chat` reads, from the ones the input names. */
export function chatFields(input: AiChatInput): Record<string, unknown> {
  const fields: Record<string, unknown> = {};
  if (input.id !== undefined) fields["id"] = input.id;
  if (input.title !== undefined) fields["title"] = input.title;
  if (input.model !== undefined) fields["model"] = input.model;
  if (input.projectId !== undefined) fields["project_id"] = input.projectId;
  if (input.agentId !== undefined) fields["agent_id"] = input.agentId;
  if (input.visibility !== undefined) fields["visibility"] = input.visibility;
  if (input.pinned !== undefined) fields["pinned"] = input.pinned;
  if (input.temporary !== undefined) fields["is_temporary"] = input.temporary;
  if (input.ownerId !== undefined) fields["owner_id"] = input.ownerId;
  return fields;
}

export function patchFields(patch: AiChatPatch): Record<string, unknown> {
  const fields: Record<string, unknown> = {};
  if (patch.title !== undefined) fields["title"] = patch.title;
  if (patch.model !== undefined) fields["model"] = patch.model;
  if (patch.projectId !== undefined) fields["project_id"] = patch.projectId;
  if (patch.visibility !== undefined) fields["visibility"] = patch.visibility;
  if (patch.pinned !== undefined) fields["pinned"] = patch.pinned;
  if (patch.archived !== undefined) fields["archived"] = patch.archived;
  return fields;
}

export function projectFields(input: AiProjectInput): Record<string, unknown> {
  const fields: Record<string, unknown> = {};
  if (input.name !== undefined) fields["name"] = input.name;
  if (input.instructions !== undefined) {
    fields["instructions"] = input.instructions;
  }
  if (input.defaultModel !== undefined) {
    fields["default_model"] = input.defaultModel;
  }
  if (input.pinned !== undefined) fields["pinned"] = input.pinned;
  if (input.archived !== undefined) fields["archived"] = input.archived;
  return fields;
}

export const canonical = (message: AiMessage): Record<string, unknown> => ({
  id: message.id,
  role: message.role,
  parts: message.parts,
  ...(message.metadata === undefined ? {} : { metadata: message.metadata }),
});

/**
 * The chat block over the `ai-chat` SQL module: chats with a message tree,
 * projects, stream claims, tool approvals, feedback, share links, the model
 * catalog and moderation events. It names no AI SDK; the adapters in
 * `better-supabase/ai-sdk` convert to and from it.
 */
