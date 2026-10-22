"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { customerAttachments } from "@/features/customers/customer-attachments";
import { can } from "@/features/user/user-permissions";
import { blocks } from "@/lib/blocks";
import { bsb } from "@/lib/supabase/server";

import { summaryMessaging, threadSummarizer } from "./chat-summaries";

const Id = v.pipe(v.string(), v.uuid());
const MAX_FILE_BYTES = 25 * 1024 * 1024;

/** A channel as the browse dialog shows it. */
export interface ChannelRow {
  readonly id: string;
  readonly name: string;
  readonly topic: string | null;
  readonly visibility: "public" | "private";
  readonly memberCount: number;
  readonly joined: boolean;
}

/** Every channel the caller can see, joined or not. */
export const browseChannels = bsb.action(
  { requireTenant: true },
  async (_input, { tenant, supabase }) => {
    const listed = await blocks(supabase, tenant).channels.list({
      browse: true,
    });

    return listed.ok
      ? ok(
          listed.data.map((channel): ChannelRow => ({
            id: channel.id,
            name: channel.name,
            topic: channel.topic ?? null,
            visibility: channel.visibility,
            memberCount: channel.memberCount,
            joined: channel.role !== undefined,
          })),
        )
      : listed;
  },
);

export const createChannel = bsb.action(
  {
    input: v.object({
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(80)),
      topic: v.pipe(v.string(), v.trim(), v.maxLength(250)),
      visibility: v.picklist(["public", "private"]),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "channels.create"),
  },
  async ({ name, topic, visibility }, { tenant, supabase }) => {
    const created = await blocks(supabase, tenant).channels.create({
      name,
      visibility,
      topic: topic === "" ? undefined : topic,
    });

    return created.ok ? ok(created.data.id) : created;
  },
);

export const joinChannel = bsb.action(
  { input: v.object({ channelId: Id }), requireTenant: true },
  async ({ channelId }, { tenant, supabase }) =>
    blocks(supabase, tenant).channels.join(channelId),
);

/**
 * The first half of a file on a message: a pending attachment on the
 * conversation and a signed upload URL. The browser uploads the bytes, then
 * `confirmChatUpload`; `send` moves the file onto the message.
 */
export const startChatUpload = bsb.action(
  {
    input: v.object({
      conversationId: Id,
      name: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(255)),
      mimeType: v.pipe(v.string(), v.maxLength(255)),
      size: v.pipe(
        v.number(),
        v.integer(),
        v.minValue(1),
        v.maxValue(MAX_FILE_BYTES),
      ),
    }),
    requireTenant: true,
    authorize: (session) => can(session, "messages.send"),
  },
  async ({ conversationId, name, mimeType, size }, { tenant, supabase }) => {
    const upload = await customerAttachments(supabase, tenant).upload(
      { type: "conversation", id: conversationId },
      {
        name,
        mimeType: mimeType === "" ? "application/octet-stream" : mimeType,
        size,
      },
    );

    if (!upload.ok) {
      return upload;
    }

    const { attachment, token } = upload.data;

    return ok({
      id: attachment.id,
      bucket: attachment.bucket,
      path: attachment.path,
      token,
    });
  },
);

export const confirmChatUpload = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    authorize: (session) => can(session, "messages.send"),
  },
  async ({ id }, { supabase }) => {
    const confirmed = await customerAttachments(supabase).confirm(id);

    return confirmed.ok ? ok(id) : confirmed;
  },
);

/** A thread summary as the thread panel shows it. */
export interface ThreadSummaryRow {
  readonly summary: string;
  readonly messageCount: number;
  readonly stale: boolean;
}

/**
 * Summarizes a thread for someone who missed it. A current summary comes back
 * without a model call; `force` writes a new one.
 */
export const summarizeThread = bsb.action(
  {
    input: v.object({ threadId: Id, force: v.optional(v.boolean(), false) }),
    requireTenant: true,
  },
  async ({ threadId, force }, { tenant, supabase }) => {
    const summary = await summaryMessaging(supabase, tenant).summarize(
      { threadId },
      threadSummarizer(supabase),
      { force },
    );

    return summary.ok
      ? ok({
          summary: summary.data.summary,
          messageCount: summary.data.messageCount,
          stale: summary.data.stale,
        } satisfies ThreadSummaryRow)
      : summary;
  },
);
