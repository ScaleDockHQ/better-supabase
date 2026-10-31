import { describe, expect, it, vi } from "vitest";

import type {
  RouteOptimizer,
  RouteRequest,
} from "../../../src/blocks/dispatch/index.ts";

import {
  distanceMeters,
  fetchRouteOptimizer,
  nearestNeighbourOptimizer,
  optimizeStops,
  planVisits,
  routeLengthMeters,
  routeOptimizerOf,
} from "../../../src/blocks/dispatch/index.ts";

const HOME = { latitude: 52, longitude: 5 };

const REQUEST: RouteRequest = {
  start: HOME,
  stops: [
    {
      id: "far",
      point: { latitude: 52.5, longitude: 5.5 },
      durationMinutes: 30,
    },
    {
      id: "near",
      point: { latitude: 52.01, longitude: 5.01 },
      durationMinutes: 30,
    },
    {
      id: "mid",
      point: { latitude: 52.2, longitude: 5.2 },
      durationMinutes: 30,
    },
  ],
};

const reference: RouteOptimizer = {
  apiVersion: 1,
  name: "reference",
  optimize: (request) =>
    Promise.resolve({
      order: request.stops.map((stop) => stop.id).toSorted(),
      durationSeconds: 1200,
    }),
};

describe("route optimizer", () => {
  it("measures great-circle distances", () => {
    expect(distanceMeters(HOME, HOME)).toBe(0);
    expect(
      Math.round(
        distanceMeters(
          { latitude: 0, longitude: 0 },
          { latitude: 0, longitude: 1 },
        ),
      ),
    ).toBe(111_195);
  });

  it("orders by nearest neighbour from the start", async () => {
    const answer = await nearestNeighbourOptimizer().optimize(REQUEST);

    expect(answer.order).toEqual(["near", "mid", "far"]);
    expect(answer.distanceMeters).toBeGreaterThan(0);
  });

  it("starts at the first closest stop without a start and breaks ties by order", async () => {
    const same = { latitude: 1, longitude: 1 };

    const answer = await nearestNeighbourOptimizer().optimize({
      stops: [
        { id: "a", point: same },
        { id: "b", point: same },
      ],
    });

    expect(answer.order).toEqual(["a", "b"]);
    expect(
      (await nearestNeighbourOptimizer().optimize({ stops: [] })).order,
    ).toEqual([]);
  });

  it("adds the end point to the route length and skips unknown ids", () => {
    const withEnd = routeLengthMeters({ ...REQUEST, end: HOME }, [
      "near",
      "ghost",
    ]);

    const open = routeLengthMeters(REQUEST, ["near"]);

    expect(withEnd).toBeGreaterThan(open);
    expect(
      routeLengthMeters({ stops: REQUEST.stops }, ["near", "far"]),
    ).toBeGreaterThan(0);
  });

  it("rejects an optimizer for another API version", () => {
    expect(() =>
      routeOptimizerOf({
        ...reference,
        apiVersion: 2,
      } as unknown as RouteOptimizer),
    ).toThrow("supports 1");
  });

  it("uses the optimizer's order when it is valid", async () => {
    const answer = await optimizeStops(reference, REQUEST);

    expect(answer.source).toBe("optimizer");
    expect(answer.order).toEqual(["far", "mid", "near"]);
    expect(answer.durationSeconds).toBe(1200);
  });

  it("falls back when the optimizer throws, repeats or invents a stop", async () => {
    const failing: RouteOptimizer = {
      ...reference,
      optimize: () => Promise.reject(new Error("down")),
    };

    const stringFailure: RouteOptimizer = {
      ...reference,
      optimize: () => Promise.reject("boom"),
    };

    const repeats: RouteOptimizer = {
      ...reference,
      optimize: () => Promise.resolve({ order: ["far", "far", "mid"] }),
    };

    const invents: RouteOptimizer = {
      ...reference,
      optimize: () => Promise.resolve({ order: ["far", "mid", "ghost"] }),
    };

    const down = await optimizeStops(failing, REQUEST);

    expect(down.source).toBe("fallback");
    expect(down.fallbackReason).toBe("down");
    expect(down.order).toEqual(["near", "mid", "far"]);
    expect((await optimizeStops(stringFailure, REQUEST)).fallbackReason).toBe(
      "boom",
    );
    expect((await optimizeStops(repeats, REQUEST)).fallbackReason).toContain(
      "not the request's stops",
    );
    expect((await optimizeStops(invents, REQUEST)).source).toBe("fallback");
  });

  it("posts the request to a service and reads the order back", async () => {
    const fetcher = vi.fn(() =>
      Promise.resolve(
        Response.json({
          order: ["mid", "near", "far"],
          distanceMeters: 5,
          durationSeconds: 9,
        }),
      ),
    );

    const optimizer = fetchRouteOptimizer({
      url: "https://routes.example/optimize",
      headers: { authorization: "Bearer k" },
      fetch: fetcher,
      name: "routes",
    });

    const answer = await optimizeStops(optimizer, REQUEST);

    expect(optimizer.name).toBe("routes");
    expect(answer).toMatchObject({
      source: "optimizer",
      order: ["mid", "near", "far"],
      distanceMeters: 5,
      durationSeconds: 9,
    });
    expect(fetcher).toHaveBeenCalledWith(
      "https://routes.example/optimize",
      expect.objectContaining({
        method: "POST",
        headers: {
          "content-type": "application/json",
          authorization: "Bearer k",
        },
      }),
    );
  });

  it("falls back on a service error or an answer without an order", async () => {
    const error = fetchRouteOptimizer({
      url: "https://routes.example/optimize",
      fetch: () => Promise.resolve(new Response("no", { status: 503 })),
    });

    const empty = fetchRouteOptimizer({
      url: "https://routes.example/optimize",
      fetch: () => Promise.resolve(Response.json({ order: "x" })),
    });

    const notObject = fetchRouteOptimizer({
      url: "https://routes.example/optimize",
      fetch: () => Promise.resolve(Response.json(null)),
    });

    const bareOrder = fetchRouteOptimizer({
      url: "https://routes.example/optimize",
      fetch: () =>
        Promise.resolve(
          Response.json({ order: ["near", "mid", "far"], distanceMeters: "x" }),
        ),
    });

    expect(error.name).toBe("http");
    expect((await optimizeStops(error, REQUEST)).fallbackReason).toBe(
      "route optimizer answered 503",
    );
    expect((await optimizeStops(empty, REQUEST)).fallbackReason).toBe(
      "route optimizer answered without an order",
    );
    expect((await optimizeStops(notObject, REQUEST)).source).toBe("fallback");
    expect(await optimizeStops(bareOrder, REQUEST)).not.toHaveProperty(
      "distanceMeters",
    );
  });

  it("walks a shift along the order and flags visits past its end", async () => {
    const shift = {
      startsAt: Temporal.Instant.from("2026-10-22T08:00:00Z"),
      endsAt: Temporal.Instant.from("2026-10-22T09:45:00Z"),
    };

    const stops = REQUEST.stops.map((stop) => ({
      ...stop,
      durationMinutes: 30,
    }));

    const plan = await planVisits(shift, stops, {
      start: HOME,
      end: HOME,
      averageSpeedKmh: 60,
    });

    expect(plan.optimization.order).toEqual(["near", "mid", "far"]);
    expect(plan.visits.map((visit) => visit.id)).toEqual([
      "near",
      "mid",
      "far",
    ]);
    expect(plan.visits[0]?.withinShift).toBe(true);
    expect(plan.visits[2]?.withinShift).toBe(false);
    expect(plan.visits[1]?.arriveAt.epochNanoseconds).toBeGreaterThan(
      plan.visits[0]?.leaveAt.epochNanoseconds ?? 0n,
    );

    const open = await planVisits(shift, stops, { optimizer: reference });

    expect(open.optimization.source).toBe("optimizer");
    expect(open.visits[0]?.arriveAt.toString()).toBe("2026-10-22T08:00:00Z");
  });
});
