import type {
  RouteOptimization,
  RouteOptimizer,
  RouteRequest,
} from "better-supabase/blocks/dispatch";

import type { HttpOptions } from "./http.ts";

import { list, numberOf, record, requestJson, text } from "./http.ts";

/**
 * A `RouteOptimizer` over a routing service (ADR 0158). The port promises every
 * stop id once, so the adapter checks the answer and throws when the service
 * drops or repeats a stop; the block then falls back to its nearest-neighbour
 * order.
 */
export function createRouteOptimizer(options: HttpOptions): RouteOptimizer {
  return {
    apiVersion: 1,
    name: "example-router",
    async optimize(request: RouteRequest): Promise<RouteOptimization> {
      const body = await requestJson(options, "/optimize", {
        method: "POST",
        body: request,
      });

      if (!body.ok) {
        throw new Error(body.error.message);
      }

      const answer = record(body.data, "optimization");

      const order = list(answer.order, "order").map((id) =>
        text(id, "order[]"),
      );

      const expected = request.stops.map((stop) => stop.id).toSorted();

      if (JSON.stringify(order.toSorted()) !== JSON.stringify(expected)) {
        throw new Error("the router must return every stop id exactly once");
      }

      return {
        order,
        ...(answer.distanceMeters === undefined
          ? {}
          : {
              distanceMeters: numberOf(answer.distanceMeters, "distanceMeters"),
            }),
        ...(answer.durationSeconds === undefined
          ? {}
          : {
              durationSeconds: numberOf(
                answer.durationSeconds,
                "durationSeconds",
              ),
            }),
      };
    },
  };
}
