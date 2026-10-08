"use server";

import { aiFileUrl } from "better-supabase/blocks/ai-files";
import * as v from "valibot";

import { can } from "@/features/user/user-permissions";
import { bs } from "@/lib/supabase/server";

import { aiFiles } from "./assistant-server";

/** 10 MB: a signed upload; larger files would use TUS. */
const MAX_SIZE = 10 * 1024 * 1024;

/**
 * Reserves an attachment for the caller and returns where to upload it.
 * The bucket only accepts the upload at the reserved path.
 */
export const reserveAttachment = bs.action(
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
    authorize: (session) => can(session, "ai_chat.create"),
  },
  ({ filename, mediaType, size, chatId }, { tenant, supabase }) =>
    aiFiles(supabase)
      .files.upload(tenant, { filename, mediaType, size, chatId })
      .map(({ file, token }) => ({
        id: file.id,
        bucket: file.bucket,
        path: file.path,
        token,
      })),
);

/** Marks the upload done and returns the file part the message holds. */
export const confirmAttachment = bs.action(
  {
    input: v.object({ id: v.pipe(v.string(), v.uuid()) }),
    requireTenant: true,
    authorize: (session) => can(session, "ai_chat.create"),
  },
  ({ id }, { supabase }) =>
    aiFiles(supabase)
      .files.confirm(id)
      .map((file) => ({
        type: "file" as const,
        mediaType: file.mediaType,
        filename: file.filename,
        url: aiFileUrl(file),
      })),
);
