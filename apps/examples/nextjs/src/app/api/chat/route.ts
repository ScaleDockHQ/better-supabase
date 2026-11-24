import { dbError, err } from "better-supabase";
import * as v from "valibot";

import {
  assistant,
  assistantContext,
} from "../../../features/assistant/assistant-server";
import {
  PageContextBody,
  pageContextOfBody,
} from "../../../features/assistant/page-context";
import { bsbShell as bsb } from "../../../lib/supabase/server-shell";

/**
 * `POST /api/chat`: stores the user's message and streams the answer. The body
 * may carry the page the assistant was opened from, which scopes its tools to
 * what the caller may read.
 */
export const POST = bsb.route(
  async (request, { session, tenant, supabase, db }) => {
    if (session.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to use the assistant"));
    }

    const pending = db.permissions.permissions();

    const raw: unknown = await request
      .clone()
      .json()
      .catch(() => null);

    const permissions = await pending;
    const body = v.safeParse(PageContextBody, raw);

    return assistant().respond(
      request,
      assistantContext(
        supabase,
        session.user.id,
        tenant,
        pageContextOfBody(body),
        permissions.ok ? permissions.data : null,
      ),
    );
  },
  { requireTenant: true },
);
