import { describe, expect, it } from "vitest";

import type { CloudEvent } from "../../src/events/cloud-event.ts";

import {
  DEFAULT_TYPE_PREFIX,
  eventTypeOf,
  stripTypePrefix,
} from "../../src/events/cloud-event.ts";

describe("stripTypePrefix", () => {
  it("removes the default prefix and its dot", () => {
    expect(stripTypePrefix(`${DEFAULT_TYPE_PREFIX}.order.paid`)).toBe(
      "order.paid",
    );
  });

  it("takes a custom prefix with or without a trailing dot", () => {
    expect(stripTypePrefix("acme.order.paid", "acme")).toBe("order.paid");
    expect(stripTypePrefix("acme.order.paid", "acme.")).toBe("order.paid");
  });

  it("leaves other types unchanged", () => {
    expect(stripTypePrefix("other.order.paid", "acme")).toBe(
      "other.order.paid",
    );
  });
});

describe("eventTypeOf", () => {
  const event = (
    type: string,
    extra: Record<string, unknown> = {},
  ): CloudEvent => ({
    specversion: "1.0",
    id: "1",
    source: "app",
    type,
    ...extra,
  });

  it("strips the prefix from the type", () => {
    expect(eventTypeOf(event(`${DEFAULT_TYPE_PREFIX}.task.created`))).toBe(
      "task.created",
    );
    expect(eventTypeOf(event("acme.task.created"), "acme")).toBe(
      "task.created",
    );
  });

  it("prefers the current type a legacy relay sent", () => {
    expect(
      eventTypeOf(
        event(`${DEFAULT_TYPE_PREFIX}.work_item.created`, {
          currenttype: "task.created",
        }),
      ),
    ).toBe("task.created");
    expect(
      eventTypeOf(
        event(`${DEFAULT_TYPE_PREFIX}.task.created`, { currenttype: "" }),
      ),
    ).toBe("task.created");
  });
});
