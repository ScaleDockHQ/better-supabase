import "server-only";
import type { UIMessage } from "ai";

import { toUIMessages } from "better-supabase/ai-sdk";
import { tenantOf } from "better-supabase/next";

import { getSession } from "@/features/user/user-queries";
import { bs } from "@/lib/supabase/server";

import { aiChat, aiRuns } from "./assistant-server";

export interface ChatRow {
  readonly id: string;
  readonly title: string;
  /** ISO 8601. */
  readonly lastMessageAt: string;
}

/**
 * The caller's chats in the active organization, newest first. Not cached:
 * a chat's title and order change with every answer.
 */
export async function getChats(): Promise<readonly ChatRow[]> {
  const [session, { supabase }] = await Promise.all([
    getSession(),
    bs.context(),
  ]);
  const organizationId = tenantOf(session);
  if (!organizationId) return [];
  const page = await aiChat(supabase)
    .chats.list({ organizationId, size: 50 })
    .orThrow();
  return page.items.map((chat) => ({
    id: chat.id,
    title: chat.title,
    lastMessageAt: chat.lastMessageAt.toString(),
  }));
}

export interface StoredChatData {
  readonly messages: UIMessage[];
  /** An answer is still being written. */
  readonly streaming: boolean;
  /** The latest answer ran as a workflow. */
  readonly durable: boolean;
}

/** The active branch of a chat as UI messages; `undefined` when it doesn't exist yet. */
export async function getStoredChat(
  chatId: string,
): Promise<StoredChatData | undefined> {
  const { supabase } = await bs.context();
  const chats = aiChat(supabase);
  const chat = await chats.chats.get(chatId);
  if (!chat.ok) {
    if (chat.error.kind === "not_found") return undefined;
    throw new Error(chat.error.message);
  }
  const [path, runs] = await Promise.all([
    chats.messages.path(chatId, { native: true }).orThrow(),
    aiRuns(supabase).list({ chatId, size: 1 }).orThrow(),
  ]);
  return {
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
  const { supabase } = await bs.context();
  const runs = aiRuns(supabase);
  const [recent, pending] = await Promise.all([
    runs.list({ size: 20 }).orThrow(),
    runs.pendingApprovals(50).orThrow(),
  ]);
  const withSteps = await Promise.all(
    recent.map(async (run) => ({
      id: run.id,
      chatId: run.chatId,
      status: run.status,
      engine: run.engine,
      model: run.model,
      startedAt: run.startedAt.toString(),
      steps:
        run.engine === "workflow"
          ? (await runs.steps.list(run.id).orThrow()).map((step) => ({
              key: step.key,
              label: step.label,
              status: step.status,
            }))
          : [],
    })),
  );
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
