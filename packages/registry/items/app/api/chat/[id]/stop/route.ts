import { dbError, err } from "better-supabase";

import { assistant, assistantContext } from "@/lib/assistant";
import { bsb } from "@/lib/supabase/server";

/** `POST /api/chat/[id]/stop`: ends the running answer; it is stored as stopped. */
export const POST = bsb.route<{ id: string }, true>(
  (_request, { session, tenant, supabase, params }) =>
    session.kind === "user"
      ? assistant().stop(
          params.id,
          assistantContext(supabase, session.user.id, tenant),
        )
      : err(dbError("unauthorized", "Sign in to use the assistant")),
  { requireTenant: true },
);
