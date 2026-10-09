import { dbError, err } from "better-supabase";

import { durableAvailable } from "../../../../features/assistant/assistant-server";
import {
  agentOf,
  durable,
  durableContext,
} from "../../../../features/assistant/durable/durable-server";
import { bs } from "../../../../lib/supabase/server";

/**
 * `POST /api/chat/durable`: starts the turn's workflow, or decides its
 * approvals, and streams the answer with the `x-workflow-run-id` header.
 */
export const POST = bs.route(
  async (request, { session, tenant, supabase }) => {
    if (session.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to use the assistant"));
    }
    if (!durableAvailable()) {
      return err(
        dbError("unsupported", "Durable chats need AI_GATEWAY_API_KEY"),
      );
    }
    const agent = await agentOf(request);
    return durable(agent).respond(
      request,
      durableContext(supabase, session.user.id, tenant),
    );
  },
  { requireTenant: true },
);
