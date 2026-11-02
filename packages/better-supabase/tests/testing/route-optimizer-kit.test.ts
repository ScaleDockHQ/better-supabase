import { describe, expect, it } from "vitest";

import type { RouteOptimizer } from "../../src/blocks/dispatch/route-optimizer.ts";

import { nearestNeighbourOptimizer } from "../../src/blocks/dispatch/route-optimizer.ts";
import {
  ConformanceError,
  testRouteOptimizer,
} from "../../src/testing/index.ts";

const broken = (optimize: RouteOptimizer["optimize"]): RouteOptimizer => ({
  apiVersion: 1,
  name: "broken",
  optimize,
});

describe("testRouteOptimizer", () => {
  it("passes the nearest-neighbour optimizer", async () => {
    await expect(
      testRouteOptimizer(nearestNeighbourOptimizer()),
    ).resolves.toBeDefined();
  });

  it("fails an order that drops a stop", async () => {
    await expect(
      testRouteOptimizer(
        broken((request) =>
          Promise.resolve({ order: request.stops.slice(1).map((s) => s.id) }),
        ),
      ),
    ).rejects.toBeInstanceOf(ConformanceError);
  });

  it("fails a negative total", async () => {
    const real = nearestNeighbourOptimizer();

    await expect(
      testRouteOptimizer(
        broken(async (request) => ({
          ...(await real.optimize(request)),
          distanceMeters: -1,
        })),
      ),
    ).rejects.toBeInstanceOf(ConformanceError);
  });
});
