import type { DbError } from "../../core/errors.ts";
import type { EventHub } from "../../core/events.ts";
import type { WorkflowEditor } from "./types.ts";

import { dbError } from "../../core/errors.ts";

/** Where `subscribeEventTriggers` reports a start that failed. */
export interface EventTriggerOptions {
  readonly onError?: (failure: {
    readonly error: DbError;
    readonly eventType: string;
  }) => void;
}

/**
 * Starts the runs of `event` triggers from the block events a `betterSupabase`
 * instance emits (`betterSupabase.on('block', ...)`), through
 * `editor.triggers.fire`. Like every event handler it only observes: a failed
 * start goes to `onError` and never changes the result of the work that emitted
 * the event (invariant 5). Returns a function that stops listening.
 *
 * ```ts
 * subscribeEventTriggers(betterSupabase, serviceBuilder);
 * ```
 */
export function subscribeEventTriggers(
  betterSupabase: { readonly events: Pick<EventHub, "on"> },
  editor: Pick<WorkflowEditor, "triggers">,
  options: EventTriggerOptions = {},
): () => void {
  return betterSupabase.events.on("block", (event) => {
    const report = (error: DbError): void => {
      try {
        options.onError?.({ error, eventType: event.type });
      } catch {
        // The reporter is an observer too.
      }
    };

    const start = async (): Promise<void> => {
      const result = await editor.triggers.fire({
        type: event.type,
        data: event.data,
        ...(event.tenant === undefined ? {} : { tenant: event.tenant }),
        ...(event.subject === undefined ? {} : { subject: event.subject }),
        time: event.time.toString(),
      });

      if (!result.ok) {
        report(result.error);
      }
    };

    start().catch((cause: unknown) => {
      report(
        dbError(
          "aborted",
          cause instanceof Error ? cause.message : String(cause),
        ),
      );
    });
  });
}
