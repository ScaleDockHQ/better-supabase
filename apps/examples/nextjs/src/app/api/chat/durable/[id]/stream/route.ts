import { dbError, err } from "better-supabase";

import {
  durable,
  durableContext,
} from "../../../../../../features/assistant/durable/durable-server";
import { bs } from "../../../../../../lib/supabase/server";

/** `GET /api/chat/durable/[id]/stream?startIndex=`: reconnects to the running turn, or 204. */
export const GET = bs.route<{ id: string }, true>(
  (request, { session, tenant, supabase, params }) => {
    if (session.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to use the assistant"));
    }
    const startIndex = Number(
      new URL(request.url).searchParams.get("startIndex") ?? 0,
    );
    return durable().resume(
      params.id,
      durableContext(supabase, session.user.id, tenant),
      {
        startIndex: Number.isSafeInteger(startIndex) ? startIndex : 0,
        signal: request.signal,
      },
    );
  },
  { requireTenant: true },
);
