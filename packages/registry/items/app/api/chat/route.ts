import { dbError, err } from "better-supabase";

import { assistant, assistantContext } from "@/lib/assistant";
import { bsb } from "@/lib/supabase/server";

/** `POST /api/chat`: stores the member's message and streams the answer. */
export const POST = bsb.route(
  (request, { session, tenant, supabase }) =>
    session.kind === "user"
      ? assistant().respond(
          request,
          assistantContext(supabase, session.user.id, tenant),
        )
      : err(dbError("unauthorized", "Sign in to use the assistant")),
  { requireOrganization: true },
);
