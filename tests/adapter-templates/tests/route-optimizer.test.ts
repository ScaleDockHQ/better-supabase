import { describe, expect, it } from "vitest";

import { createRouteOptimizer } from "../src/route-optimizer.ts";
import { fakeFetch, OPTIONS } from "./fake-fetch.ts";

const request = {
  start: { latitude: 52.37, longitude: 4.89 },
  stops: [
    { id: "a", point: { latitude: 52.1, longitude: 5.1 } },
    { id: "b", point: { latitude: 52, longitude: 4.4 } },
  ],
};

describe("route optimizer", () => {
  it("returns the service order and its totals", async () => {
    const optimizer = createRouteOptimizer({
      ...OPTIONS,
      fetch: fakeFetch(() => ({
        json: { order: ["b", "a"], distanceMeters: 5000, durationSeconds: 600 },
      })).fetch,
    });

    expect(optimizer.apiVersion).toBe(1);
    await expect(optimizer.optimize(request)).resolves.toEqual({
      order: ["b", "a"],
      distanceMeters: 5000,
      durationSeconds: 600,
    });
  });

  it("rejects an answer that drops or repeats a stop", async () => {
    for (const order of [["a"], ["a", "a"], ["a", "b", "c"]]) {
      const optimizer = createRouteOptimizer({
        ...OPTIONS,
        fetch: fakeFetch(() => ({ json: { order } })).fetch,
      });

      await expect(optimizer.optimize(request)).rejects.toThrow(/exactly once/);
    }
  });

  it("rejects when the service fails", async () => {
    const optimizer = createRouteOptimizer({
      ...OPTIONS,
      fetch: fakeFetch(() => ({ status: 503 })).fetch,
    });

    await expect(optimizer.optimize(request)).rejects.toThrow(/503|HTTP/);
  });
});
