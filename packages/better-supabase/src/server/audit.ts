import type { EventHub } from "../core/events.ts";
import type { CloudEvent, EventSink } from "../events/index.ts";

import { forwardBlockEvents } from "../events/index.ts";

/** The CloudEvents `source` of the events the server sends to its `audit` sink. */
export const SERVER_EVENT_SOURCE = "/better-supabase/server";

export type AccountEventType =
  | "account.suspended"
  | "account.unsuspended"
  | "account.deleted"
  | "account.sessions_ended";

export interface ServerAudit {
  /** Sends one account event; failures go to the logger and never change a result. */
  account(
    type: AccountEventType,
    userId: string,
    data: Readonly<Record<string, unknown>>,
  ): void;
}

const OFF: ServerAudit = { account: () => undefined };

/**
 * The server's audit trail: account actions are sent to `sink` as CloudEvents
 * typed `dev.better-supabase.account.*` with subject `users/<id>`, and
 * `support.denied` block events are forwarded to it.
 */
export function serverAudit(
  betterSupabase: { readonly events: EventHub },
  sink: EventSink | undefined,
): ServerAudit {
  if (sink === undefined) return OFF;
  const { events } = betterSupabase;
  forwardBlockEvents(betterSupabase, sink, {
    source: SERVER_EVENT_SOURCE,
    types: ["support.denied"],
  });
  const report = (cause: unknown): void => {
    events.logger.error("audit sink failed", { cause });
  };
  return {
    account(type, userId, data) {
      const event: CloudEvent = {
        specversion: "1.0",
        id: crypto.randomUUID(),
        source: SERVER_EVENT_SOURCE,
        type: `dev.better-supabase.${type}`,
        subject: `users/${userId}`,
        time: new Date().toISOString(),
        datacontenttype: "application/json",
        data: { userId, ...data },
      };
      try {
        events.track(Promise.resolve(sink.send([event])).catch(report));
      } catch (cause) {
        report(cause);
      }
    },
  };
}
