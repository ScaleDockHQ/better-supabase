import type { RequestContext } from "better-supabase";

import { createNotifications } from "better-supabase/blocks/notifications";
import { rpcTransport } from "better-supabase/blocks/organizations";
import { Temporal } from "temporal-polyfill";

import { serviceSupabase } from "@/lib/service-supabase";

import {
  notificationTypes,
  renderNotification,
} from "../notifications/notification-types";

/**
 * Steps run in the workflow's step route, outside any request, so they act
 * through the service role. The tenant and the recipient come from the context
 * the run was started with (`workflowContext`), never from input. The step
 * bundle doesn't load `@/lib/supabase`, so it passes Temporal itself.
 */
export { serviceSupabase };

export function serviceNotifications() {
  return createNotifications({
    transport: rpcTransport(serviceSupabase(), { schema: "api" }),
    schema: "api",
    types: notificationTypes,
    render: renderNotification,
    temporal: Temporal,
  });
}

/** Sends the run's actor a notification in the run's tenant. */
export async function notifyActor(
  context: RequestContext,
  title: string,
): Promise<void> {
  "use step";

  if (context.tenant === undefined || context.actor?.kind !== "user") {
    return;
  }

  await serviceNotifications()
    .send({
      type: "workflow.message",
      input: {
        tenant: context.tenant,
        recipients: [context.actor.id],
        includeActor: true,
        data: { title },
      },
    })
    .orThrow();
}

export interface DocumentSummary {
  readonly words: number;
  readonly sentences: number;
  readonly preview: string;
}

/** The ingestion pipeline's parse step: counts and a preview. */
// oxlint-disable-next-line typescript/require-await -- the Workflow SDK compiles only async functions into steps.
export async function summarizeDocument(
  text: string,
): Promise<DocumentSummary> {
  "use step";
  const trimmed = text.trim();

  return {
    words: trimmed === "" ? 0 : trimmed.split(/\s+/u).length,
    sentences: trimmed.split(/[.!?]+/u).filter((part) => part.trim() !== "")
      .length,
    preview: trimmed.slice(0, 120),
  };
}
