"use server";

import { ok } from "better-supabase";
import { aiFileUrl } from "better-supabase/blocks/ai-files";
import { refresh } from "next/cache";
import * as v from "valibot";

import { bsbCore } from "@/lib/supabase/server-core";

import { aiChat, aiFiles } from "./assistant-server";

/** 10 MB: a signed upload; larger files would use TUS. */
const MAX_SIZE = 10 * 1024 * 1024;

/**
 * Reserves an attachment for the caller and returns where to upload it. The
 * bucket only accepts the upload at the reserved path.
 */
export const reserveAttachment = bsbCore.action(
  {
    input: v.object({
      filename: v.pipe(v.string(), v.minLength(1), v.maxLength(255)),
      mediaType: v.pipe(v.string(), v.minLength(3), v.maxLength(255)),
      size: v.pipe(
        v.number(),
        v.integer(),
        v.minValue(0),
        v.maxValue(MAX_SIZE),
      ),
      chatId: v.pipe(v.string(), v.uuid()),
    }),
    requireTenant: true,
    permission: "ai_chat.create",
  },
  ({ filename, mediaType, size, chatId }, { tenant, supabase }) =>
    aiFiles(supabase)
      .files.upload({
        organizationId: tenant,
        file: { filename, mediaType, size, chatId },
      })
      .map(({ file, token }) => ({
        id: file.id,
        bucket: file.bucket,
        path: file.path,
        token,
      })),
);

/** Marks the upload done and returns the file part the message holds. */
export const confirmAttachment = bsbCore.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    permission: "ai_chat.create",
  },
  ({ id }, { supabase }) =>
    aiFiles(supabase)
      .files.confirm({ fileId: id })
      .map((file) => ({
        type: "file" as const,
        mediaType: file.mediaType,
        filename: file.filename,
        url: aiFileUrl(file),
      })),
);

/** Rates one answer; a down rating is what `ai-evals` copies into a dataset. */
export const rateMessage = bsbCore.action(
  {
    input: v.object({
      chatId: v.pipe(v.string(), v.uuid()),
      messageId: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
      rating: v.picklist([-1, 0, 1]),
    }),
    requireTenant: true,
    permission: "ai_chat.create",
  },
  ({ chatId, messageId, rating }, { supabase }) =>
    aiChat(supabase)
      .feedback.rate({ chatId, messageId, rating })
      .map((feedback) => feedback.rating),
);

/** Shows another branch of a chat; the page reloads the stored path. */
export const switchChatBranch = bsbCore.action(
  {
    input: v.object({
      chatId: v.pipe(v.string(), v.uuid()),
      messageId: v.pipe(v.string(), v.minLength(1), v.maxLength(200)),
    }),
    requireTenant: true,
    permission: "ai_chat.create",
  },
  async ({ chatId, messageId }, { supabase }) => {
    const switched = await aiChat(supabase).messages.switchBranch({
      chatId,
      messageId,
    });

    if (!switched.ok) {
      return switched;
    }

    refresh();

    return ok(switched.data);
  },
);

/** Renames, pins or archives a chat. */
export const updateChat = bsbCore.action(
  {
    input: v.object({
      chatId: v.pipe(v.string(), v.uuid()),
      title: v.optional(
        v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
      ),
      pinned: v.optional(v.boolean()),
      archived: v.optional(v.boolean()),
    }),
    requireTenant: true,
    permission: "ai_chat.create",
  },
  async ({ chatId, title, pinned, archived }, { supabase }) => {
    const updated = await aiChat(supabase).chats.update({
      chatId,
      patch: {
        ...(title === undefined ? {} : { title }),
        ...(pinned === undefined ? {} : { pinned }),
        ...(archived === undefined ? {} : { archived }),
      },
    });

    if (!updated.ok) {
      return updated;
    }

    refresh();

    return ok(updated.data.id);
  },
);
