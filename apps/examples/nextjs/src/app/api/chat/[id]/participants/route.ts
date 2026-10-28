import { dbError, err } from "better-supabase";
import * as v from "valibot";

import { aiChat } from "../../../../../features/assistant/assistant-server";
import { bsb } from "../../../../../lib/supabase/server";

const addBody = v.object({
  userId: v.pipe(v.string(), v.uuid()),
  role: v.optional(v.picklist(["viewer", "editor"])),
});

const removeBody = v.object({ userId: v.pipe(v.string(), v.uuid()) });

const invalid = (issues: readonly v.BaseIssue<unknown>[]) =>
  dbError("validation", "The request body is invalid", {
    issues: issues.map((issue) => ({ message: issue.message })),
  });

/**
 * `POST /api/chat/[id]/participants`: shares the chat with a teammate. A viewer
 * reads it; an editor also sends messages. The teammate must be able to read
 * the organization's chats.
 */
export const POST = bsb.route<{ id: string }, true>(
  async (request, { supabase, params }) => {
    const body = v.safeParse(addBody, await request.json().catch(() => null));

    return body.success
      ? aiChat(supabase).participants.add(params.id, body.output.userId, {
          role: body.output.role ?? "viewer",
        })
      : err(invalid(body.issues));
  },
  { requireTenant: true },
);

/**
 * `DELETE /api/chat/[id]/participants`: the owner takes a teammate off the
 * chat, or a participant leaves it.
 */
export const DELETE = bsb.route<{ id: string }, true>(
  async (request, { supabase, params }) => {
    const body = v.safeParse(
      removeBody,
      await request.json().catch(() => null),
    );

    return body.success
      ? aiChat(supabase).participants.remove(params.id, body.output.userId)
      : err(invalid(body.issues));
  },
  { requireTenant: true },
);
