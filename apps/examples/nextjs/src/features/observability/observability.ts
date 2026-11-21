import "server-only";
import { forwardBlockEvents } from "better-supabase/events";
import { createOnRequestError } from "better-supabase/next/instrumentation";
import { registerWorkflowLifecycle } from "better-supabase/workflow-sdk";

import { betterSupabase } from "@/lib/supabase";
import { bsb } from "@/lib/supabase/server";

let onRequestError: ReturnType<typeof createOnRequestError> | undefined;

/**
 * The handler behind `onRequestError` in `instrumentation.ts`. The first call
 * also starts forwarding `request.failed` to a structured log line, which a log
 * drain picks up; swap the sink for a queue or an incident tool.
 */
export function requestErrorHandler(): ReturnType<typeof createOnRequestError> {
  if (!onRequestError) {
    forwardBlockEvents(
      betterSupabase,
      {
        send: (events) => {
          for (const event of events) {
            console.error(JSON.stringify(event));
          }
        },
      },
      {
        source: "https://example.bettersupabase.com",
        types: ["request.failed"],
      },
    );
    onRequestError = createOnRequestError(betterSupabase);
  }

  return onRequestError;
}

/**
 * Writes every workflow run that completes or fails on this server to the
 * outbox as `workflow_sdk.run_completed` and `workflow_sdk.run_failed`. Returns
 * the function that unregisters the hooks.
 */
export function registerWorkflowReports(): () => void {
  return registerWorkflowLifecycle({
    outbox: bsb.admin().outbox,
    events: betterSupabase.events,
  });
}
