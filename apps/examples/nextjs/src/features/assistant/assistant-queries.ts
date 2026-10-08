import "server-only";
import type { UIMessage } from "ai";

import { toUIMessages } from "better-supabase/ai-sdk";
import { tenantOf } from "better-supabase/next";

import { getSession } from "@/features/user/user-queries";
import { bs } from "@/lib/supabase/server";

import { aiChat } from "./assistant-server";

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

/** The active branch of a chat as UI messages; `undefined` when it doesn't exist yet. */
export async function getChatMessages(
  chatId: string,
): Promise<UIMessage[] | undefined> {
  const { supabase } = await bs.context();
  const chats = aiChat(supabase);
  const chat = await chats.chats.get(chatId);
  if (!chat.ok) {
    if (chat.error.kind === "not_found") return undefined;
    throw new Error(chat.error.message);
  }
  const path = await chats.messages.path(chatId, { native: true }).orThrow();
  return toUIMessages(path);
}
