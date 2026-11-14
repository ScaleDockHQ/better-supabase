import "server-only";
import type { UIMessage } from "ai";

import { toUIMessages } from "better-supabase/ai-sdk";
import { tenantOf } from "better-supabase/next";

import type { OpsListQuery } from "@/components/ops-list/ops-list-params";

import { getSession } from "@/features/user/user-queries";
import { bsbCore } from "@/lib/supabase/server-core";

import { aiChat, aiRuns } from "./assistant-server";

const CHAT_PAGE_SIZE = 25;

const BRANCH_LOOKUPS = 25;

export interface ChatRow {
  readonly id: string;
  readonly title: string;
  readonly model: string | undefined;
  readonly pinned: boolean;
  readonly archived: boolean;
  /** ISO 8601. */
  readonly lastMessageAt: string;
}

export interface ChatPage {
  readonly items: readonly ChatRow[];
  readonly nextCursor: string | null;
}

/**
 * One page of the caller's chats in the active organization, newest first. The
 * block searches titles and message text and pages by cursor, so the list never
 * filters in the browser. Not cached: a chat's title and order change with
 * every answer.
 */
export async function getChatPage(query: OpsListQuery): Promise<ChatPage> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsbCore.context(),
  ]);

  const organizationId = tenantOf(session);

  if (!organizationId) {
    return { items: [], nextCursor: null };
  }

  const page = await aiChat(supabase)
    .chats.list({
      organizationId,
      limit: CHAT_PAGE_SIZE,
      ...(query.q === "" ? {} : { search: query.q }),
      ...(query.cursor === null ? {} : { cursor: query.cursor }),
      ...(query.filter === "pinned" ? { pinned: true } : {}),
      archived: query.filter === "archived",
    })
    .orThrow();

  return {
    items: page.items.map((chat) => ({
      id: chat.id,
      title: chat.title,
      model: chat.model,
      pinned: chat.pinned,
      archived: chat.archivedAt !== undefined,
      lastMessageAt: chat.lastMessageAt.toString(),
    })),
    nextCursor: page.next ?? null,
  };
}

export interface ModelOption {
  readonly id: string;
  readonly name: string;
  readonly provider: string;
}

/**
 * Plain AI Gateway `provider/model` strings, offered while the catalog is
 * empty.
 */
const GATEWAY_MODELS: readonly ModelOption[] = [
  { id: "openai/gpt-5-mini", name: "GPT-5 mini", provider: "openai" },
  {
    id: "anthropic/claude-sonnet-4.5",
    name: "Claude Sonnet 4.5",
    provider: "anthropic",
  },
  {
    id: "google/gemini-2.5-flash",
    name: "Gemini 2.5 Flash",
    provider: "google",
  },
];

/**
 * The models the picker offers: the tenant's allowed catalog, or the gateway
 * strings while no catalog is loaded (the block then allows every model).
 */
export async function getModels(): Promise<readonly ModelOption[]> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bsbCore.context(),
  ]);

  const organizationId = tenantOf(session) ?? null;

  const allowed = await aiChat(supabase).models.allowed(organizationId);

  if (!allowed.ok || allowed.data.length === 0) {
    return GATEWAY_MODELS;
  }

  return allowed.data.map((model) => ({
    id: model.id,
    name: model.name,
    provider: model.provider,
  }));
}

/**
 * The alternatives of one message (an edit or a regeneration) and which one
 * shows.
 */
export interface MessageBranch {
  readonly messageId: string;
  readonly siblingIds: readonly string[];
  readonly index: number;
}

export interface StoredChatData {
  readonly title: string;
  readonly pinned: boolean;
  readonly model: string | undefined;
  /** The message the chat shows; it changes when the user picks a branch. */
  readonly leafId: string | undefined;
  readonly branches: readonly MessageBranch[];
  readonly messages: UIMessage[];
  /** An answer is still being written. */
  readonly streaming: boolean;
  /** The latest answer ran as a workflow. */
  readonly durable: boolean;
}

/**
 * The branch of a chat as UI messages: the one that ends at `leafId` (the
 * `leaf` search param, so a branch has a URL) or, without one, the active
 * branch; `undefined` when the chat doesn't exist yet. A `leafId` that is not a
 * message of this chat falls back to the active branch.
 */
export async function getStoredChat(
  chatId: string,
  leafId?: string,
): Promise<StoredChatData | undefined> {
  const { supabase } = await bsbCore.context();
  const chats = aiChat(supabase);
  const chat = await chats.chats.get(chatId);

  if (!chat.ok) {
    if (chat.error.kind === "not_found") {
      return undefined;
    }

    throw new Error(chat.error.message);
  }

  const requested =
    leafId === undefined
      ? undefined
      : await chats.messages.path({ chatId, native: true, leafId });

  const [path, runs] = await Promise.all([
    requested?.ok && requested.data.length > 0
      ? requested.data
      : chats.messages.path({ chatId, native: true }).orThrow(),
    aiRuns(supabase).list({ chatId, limit: 1 }).orThrow(),
  ]);

  // Only the user's turns branch from the UI (edit, regenerate), so a chat of
  // fifty turns reads at most twenty-five sibling lists, in one wave.
  const siblings = await Promise.all(
    path
      .filter((message) => message.role === "user")
      .slice(-BRANCH_LOOKUPS)
      .map(async (message) => ({
        messageId: message.id,
        siblings: await chats.messages
          .siblings({ chatId, messageId: message.id })
          .orThrow(),
      })),
  );

  const branches = siblings.flatMap(({ messageId, siblings: list }) =>
    list.length > 1
      ? [
          {
            messageId,
            siblingIds: list.map((sibling) => sibling.id),
            index: list.findIndex((sibling) => sibling.id === messageId),
          },
        ]
      : [],
  );

  return {
    title: chat.data.title,
    pinned: chat.data.pinned,
    model: chat.data.model,
    leafId: path.at(-1)?.id ?? chat.data.leafId,
    branches,
    messages: toUIMessages(path),
    streaming: chat.data.activeStreamId !== undefined,
    durable: runs[0]?.engine === "workflow",
  };
}

export interface ActivityRun {
  readonly id: string;
  readonly chatId: string;
  readonly status: string;
  readonly engine: string;
  readonly model: string | undefined;
  /** ISO 8601. */
  readonly startedAt: string;
  readonly steps: readonly {
    readonly key: string;
    readonly label: string;
    readonly status: string;
  }[];
}

export interface ActivityApproval {
  readonly approvalId: string;
  readonly chatId: string;
  readonly chatTitle: string;
  readonly tool: string;
  readonly input: string;
  /** ISO 8601. */
  readonly createdAt: string;
}

/** The caller's latest runs with their steps, and the approvals waiting on them. */
export async function getActivity(): Promise<{
  readonly runs: readonly ActivityRun[];
  readonly approvals: readonly ActivityApproval[];
}> {
  const { supabase } = await bsbCore.context();
  const runs = aiRuns(supabase);

  const [recent, pending] = await Promise.all([
    runs.list({ limit: 20 }).orThrow(),
    runs.pendingApprovals(50).orThrow(),
  ]);

  const steps = await runs.steps
    .listFor({
      runIds: recent
        .filter((run) => run.engine === "workflow")
        .map((run) => run.id),
      limit: 50,
    })
    .orThrow();

  const withSteps = recent.map((run) => ({
    id: run.id,
    chatId: run.chatId,
    status: run.status,
    engine: run.engine,
    model: run.model,
    startedAt: run.startedAt.toString(),
    steps: steps
      .filter((step) => step.runId === run.id)
      .map((step) => ({
        key: step.key,
        label: step.label,
        status: step.status,
      })),
  }));

  return {
    runs: withSteps,
    approvals: pending.map((approval) => ({
      approvalId: approval.approvalId,
      chatId: approval.chatId,
      chatTitle: approval.chatTitle,
      tool: approval.tool,
      input: JSON.stringify(approval.input ?? null),
      createdAt: approval.createdAt.toString(),
    })),
  };
}
