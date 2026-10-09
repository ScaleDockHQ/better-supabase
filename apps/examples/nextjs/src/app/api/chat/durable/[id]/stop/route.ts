import { dbError, err } from "better-supabase";

import {
  durable,
  durableContext,
} from "../../../../../../features/assistant/durable/durable-server";
import { bs } from "../../../../../../lib/supabase/server";

/** `POST /api/chat/durable/[id]/stop`: stops the running turn through its stop hook. */
export const POST = bs.route<{ id: string }, true>(
  (_request, { session, tenant, supabase, params }) =>
    session.kind === "user"
      ? durable().stop(
          params.id,
          durableContext(supabase, session.user.id, tenant),
        )
      : err(dbError("unauthorized", "Sign in to use the assistant")),
  { requireTenant: true },
);
