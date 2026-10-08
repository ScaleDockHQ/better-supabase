import { dbError, err } from "better-supabase";

import {
  assistant,
  assistantContext,
} from "../../../features/assistant/assistant-server";
import { bs } from "../../../lib/supabase/server";

/** `POST /api/chat`: stores the user's message and streams the answer. */
export const POST = bs.route(
  (request, { session, tenant, supabase }) =>
    session.kind === "user"
      ? assistant().respond(
          request,
          assistantContext(supabase, session.user.id, tenant),
        )
      : err(dbError("unauthorized", "Sign in to use the assistant")),
  { requireTenant: true },
);
