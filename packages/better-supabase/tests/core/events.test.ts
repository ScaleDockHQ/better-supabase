import { describe, expect, it, vi } from "vitest";

import { EventHub } from "../../src/core/events.ts";
import { silentLogger } from "../../src/core/logger.ts";

describe("EventHub", () => {
  it("warns once when one event collects many handlers", () => {
    const logger = { ...silentLogger, warn: vi.fn() };
    const hub = new EventHub(logger);
    const offs = Array.from({ length: 60 }, () => hub.on("query", () => {}));
    expect(logger.warn).toHaveBeenCalledTimes(1);
    expect(logger.warn.mock.calls[0]?.[0]).toContain('51 "query" handlers');
    for (const off of offs) off();
    expect(hub.has("query")).toBe(false);
  });

  it("reports a throwing handler and keeps calling the rest", () => {
    const logger = { ...silentLogger, error: vi.fn() };
    const hub = new EventHub(logger);
    const seen = vi.fn();
    hub.on("error", () => {
      throw new Error("boom");
    });
    hub.on("error", seen);
    hub.emit("error", { error: { kind: "unknown", message: "x" } as never });
    expect(logger.error).toHaveBeenCalledOnce();
    expect(seen).toHaveBeenCalledOnce();
  });
});
