"use server";

import { ok } from "better-supabase";
import { createDrive, rpcTransport } from "better-supabase/blocks/drive";
import * as v from "valibot";

import { blockConfig } from "@/lib/supabase/blocks.generated";
import { bsb } from "@/lib/supabase/server";

/** Next.js caps a Server Action body at 1 MB (`serverActions.bodySizeLimit`). */
const MAX_BYTES = 1_000_000;

/**
 * Sends one file through a file request link, signed in or not. The drive
 * function checks the token, its password, its uses and its rate limit, so the
 * service role here only uploads the bytes to the path it returns.
 */
export const sendToFileRequest = bsb.action(
  {
    input: v.object({
      token: v.pipe(v.string(), v.regex(/^[0-9a-f]{32,128}$/)),
      file: v.pipe(v.file(), v.minSize(1), v.maxSize(MAX_BYTES)),
      password: v.optional(v.pipe(v.string(), v.maxLength(200))),
    }),
    allow: ["none", "user"],
  },
  async ({ token, file, password }) => {
    const service = bsb.admin().$client;

    const drive = createDrive({
      transport: rpcTransport(service, { schema: blockConfig.drive.api }),
      storage: service.storage,
      schema: blockConfig.drive.api,
    });

    const sent = await (password
      ? drive.uploadToRequest(token, file, { name: file.name, password })
      : drive.uploadToRequest(token, file, { name: file.name }));

    if (!sent.ok) {
      return sent;
    }

    return ok(
      sent.data.passwordRequired
        ? { passwordRequired: true as const }
        : { passwordRequired: false as const, name: file.name },
    );
  },
);
