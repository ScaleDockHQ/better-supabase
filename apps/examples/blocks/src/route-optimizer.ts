import type {
  PlannedVisits,
  RouteOptimization,
  RouteOptimizer,
  RouteRequest,
} from "better-supabase/blocks/dispatch";

import { planVisits } from "better-supabase/blocks/dispatch";

/**
 * A custom `RouteOptimizer`: visits the stops from west to east. A real one
 * calls a routing service; the port only needs every stop id once, in order.
 */
export const westToEastOptimizer: RouteOptimizer = {
  apiVersion: 1,
  name: "west-to-east",
  optimize(request: RouteRequest): Promise<RouteOptimization> {
    const order = request.stops
      .toSorted((a, b) => a.point.longitude - b.point.longitude)
      .map((stop) => stop.id);

    return Promise.resolve({ order });
  },
};

/** Plans one caregiver's shift with the custom optimizer. */
export function planShift(
  shift: Parameters<typeof planVisits>[0],
  stops: Parameters<typeof planVisits>[1],
): Promise<PlannedVisits> {
  return planVisits(shift, stops, { optimizer: westToEastOptimizer });
}
