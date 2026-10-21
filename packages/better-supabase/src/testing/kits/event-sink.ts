import type { CloudEvent, EventSink } from "../../events/index.ts";
import type { ConformanceReport } from "../conformance.ts";

import { toCloudEvents } from "../../events/index.ts";
import { conform, deepFreeze, expect, frozenCopy } from "../conformance.ts";

export interface TestEventSinkOptions {
  /**
   * Events the sink delivered, for sinks that can be read back (an outbox, a
   * test queue).
   */
  readonly received?: () =>
    | readonly CloudEvent[]
    | Promise<readonly CloudEvent[]>;
}

/**
 * Proves an `EventSink` accepts empty and full batches without mutating them,
 * and delivers them when readable.
 */
export function testEventSink(
  sink: EventSink,
  options: TestEventSinkOptions = {},
): Promise<ConformanceReport> {
  const events = toCloudEvents(
    {
      table: "customers",
      kind: "insert",
      rows: [
        { id: "1", name: "Acme" },
        { id: "2", name: "Globex" },
      ],
      context: { tenant: "organization_1" },
    },
    { source: "/better-supabase/conformance" },
  );

  return conform("EventSink", [
    ["accepts an empty batch", () => sink.send(deepFreeze([]))],
    [
      "accepts a batch without mutating it",
      () => sink.send(frozenCopy(events)),
    ],
    options.received && [
      "delivers every event",
      async () => {
        const ids = new Set(
          (await options.received!()).map((event) => event.id),
        );

        const missing = events.filter((event) => !ids.has(event.id));
        expect(
          missing.length === 0,
          `${missing.length} of ${events.length} events were not delivered`,
        );
      },
    ],
  ]);
}
