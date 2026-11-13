import { describe, expect, it } from "vitest";

import {
  blockListStatus,
  blockRealtimeRefetch,
} from "../../src/blocks/block-list-status.ts";
import { dbError } from "../../src/core/errors.ts";
import { EventHub } from "../../src/core/events.ts";

describe("blockListStatus", () => {
  const error = dbError("invalid_request", "boom");

  it("reads loading, empty, ready and error from a query state", () => {
    expect(
      blockListStatus({ status: "idle", data: undefined, error: undefined }),
    ).toEqual({ kind: "loading" });
    expect(
      blockListStatus({ status: "success", data: [], error: undefined }),
    ).toEqual({ kind: "empty" });
    expect(
      blockListStatus({ status: "success", data: [1], error: undefined }),
    ).toEqual({ kind: "ready", rows: [1] });
    expect(blockListStatus({ status: "error", data: [1], error })).toEqual({
      kind: "error",
      error,
    });
  });

  it("keeps loaded rows ready while the read runs again", () => {
    expect(
      blockListStatus({ status: "loading", data: [1], error: undefined }),
    ).toEqual({ kind: "ready", rows: [1] });
  });
});

describe("blockRealtimeRefetch", () => {
  const source = { events: new EventHub() };

  const block = {
    events: { types: ["leave_request.created", "leave_type.saved", "other"] },
    entities: {
      leave_request: { realtime: true },
      leave_type: {},
      other: { realtime: true },
    },
  };

  it("subscribes to the entity's events when it declares realtime", () => {
    expect(blockRealtimeRefetch(block, "leave_request", source)).toEqual({
      source,
      types: ["leave_request.created"],
    });
  });

  it("falls back to every event when no type has the entity's prefix", () => {
    expect(blockRealtimeRefetch(block, "other", source)?.types).toEqual(
      block.events.types,
    );
  });

  it("does not subscribe without the declaration", () => {
    expect(blockRealtimeRefetch(block, "leave_type", source)).toBeUndefined();
    expect(blockRealtimeRefetch(block, "missing", source)).toBeUndefined();
  });
});
