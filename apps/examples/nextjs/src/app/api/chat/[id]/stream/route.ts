import { dbError, err } from "better-supabase";

import {
  assistant,
  assistantContext,
} from "../../../../../features/assistant/assistant-server";
import { bs } from "../../../../../lib/supabase/server";

/** `GET /api/chat/[id]/stream`: the running answer from the start, or 204. */
export const GET = bs.route<{ id: string }, true>(
  (request, { session, tenant, supabase, params }) =>
    session.kind === "user"
      ? assistant().resume(
          params.id,
          assistantContext(supabase, session.user.id, tenant),
          { signal: request.signal },
        )
      : err(dbError("unauthorized", "Sign in to use the assistant")),
  { requireTenant: true },
);
