/** A place on the map, in decimal degrees (WGS 84). */
export interface RoutePoint {
  readonly latitude: number;
  readonly longitude: number;
}

export interface RouteStop {
  /** A work order id or a booking id; the optimizer returns these back. */
  readonly id: string;
  readonly point: RoutePoint;
  /** Time spent at the stop, used to fit visits into a shift. */
  readonly durationMinutes?: number;
}

export interface RouteRequest {
  /** Where the day starts, such as the depot or the first client's home. */
  readonly start?: RoutePoint;
  /** Where the day ends; the route is open-ended when it is left out. */
  readonly end?: RoutePoint;
  readonly stops: readonly RouteStop[];
}

export interface RouteOptimization {
  /** Every stop id of the request exactly once, in driving order. */
  readonly order: readonly string[];
  readonly distanceMeters?: number;
  readonly durationSeconds?: number;
}

/**
 * Orders the stops of a route. Versioned: a breaking change ships a new
 * `apiVersion`. `better-supabase` bundles `nearestNeighbourOptimizer` and
 * `fetchRouteOptimizer`; a package for a routing service implements the port or
 * points `fetchRouteOptimizer` at it.
 */
export interface RouteOptimizer {
  readonly apiVersion: 1;
  /** The optimizer's name, such as `nearest-neighbour`. */
  readonly name: string;
  optimize(request: RouteRequest): Promise<RouteOptimization>;
}

/** Checks the optimizer's `apiVersion` before using it. */
export function routeOptimizerOf(optimizer: RouteOptimizer): RouteOptimizer {
  const version: unknown = optimizer.apiVersion;

  if (version !== 1) {
    throw new TypeError(
      `route optimizer "${optimizer.name}" targets route optimizer API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the optimizer for API 1.`,
    );
  }

  return optimizer;
}

const EARTH_RADIUS_METERS = 6_371_008.8;

const radians = (degrees: number): number => (degrees * Math.PI) / 180;

/** The great-circle distance between two points, in meters. */
export function distanceMeters(from: RoutePoint, to: RoutePoint): number {
  const dLat = radians(to.latitude - from.latitude);
  const dLon = radians(to.longitude - from.longitude);

  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(radians(from.latitude)) *
      Math.cos(radians(to.latitude)) *
      Math.sin(dLon / 2) ** 2;

  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(a)));
}

/** The straight-line length of a route in the order given, in meters. */
export function routeLengthMeters(
  request: RouteRequest,
  order: readonly string[],
): number {
  const byId = new Map(request.stops.map((stop) => [stop.id, stop.point]));
  let previous = request.start;
  let total = 0;

  for (const id of order) {
    const point = byId.get(id);

    if (point === undefined) {
      continue;
    }

    if (previous !== undefined) {
      total += distanceMeters(previous, point);
    }

    previous = point;
  }

  if (request.end !== undefined && previous !== undefined) {
    total += distanceMeters(previous, request.end);
  }

  return total;
}

/**
 * The fallback optimizer: from the start (or the first stop) it always drives
 * to the closest stop left. Ties go to the earlier stop in the request, so the
 * order is stable. It needs no network and no service.
 */
export function nearestNeighbourOptimizer(): RouteOptimizer {
  return {
    apiVersion: 1,
    name: "nearest-neighbour",
    optimize: (request) => Promise.resolve(nearestNeighbour(request)),
  };
}

function nearestNeighbour(request: RouteRequest): RouteOptimization {
  const left = [...request.stops];
  const order: string[] = [];
  let current: RoutePoint | undefined = request.start;

  while (left.length > 0) {
    let best = 0;

    if (current !== undefined) {
      let bestDistance = Number.POSITIVE_INFINITY;

      for (const [index, stop] of left.entries()) {
        const distance = distanceMeters(current, stop.point);

        if (distance < bestDistance) {
          best = index;
          bestDistance = distance;
        }
      }
    }

    const [next] = left.splice(best, 1);

    // SAFETY: `best` indexes a non-empty `left`.
    const stop = next!;

    order.push(stop.id);
    current = stop.point;
  }

  return {
    order,
    distanceMeters: Math.round(routeLengthMeters(request, order)),
  };
}

export interface FetchRouteOptimizerOptions {
  /** The service endpoint; it receives a POST with the request as JSON. */
  readonly url: string;
  readonly headers?: Readonly<Record<string, string>>;
  /** Default: the global `fetch`. */
  readonly fetch?: typeof fetch;
  /** The name kept in results. Default `http`. */
  readonly name?: string;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null;

const optionalNumber = (value: unknown): number | undefined =>
  typeof value === "number" && Number.isFinite(value) ? value : undefined;

/**
 * An optimizer that posts the request as JSON to a routing service and reads `{
 * order, distanceMeters?, durationSeconds? }` back. The order has to list every
 * stop once; anything else throws, and `optimizeStops` then falls back.
 */
export function fetchRouteOptimizer(
  options: FetchRouteOptimizerOptions,
): RouteOptimizer {
  return {
    apiVersion: 1,
    name: options.name ?? "http",
    async optimize(request) {
      const response = await (options.fetch ?? fetch)(options.url, {
        method: "POST",
        headers: { "content-type": "application/json", ...options.headers },
        body: JSON.stringify(request),
      });

      if (!response.ok) {
        throw new Error(`route optimizer answered ${response.status}`);
      }

      const body: unknown = await response.json();

      if (!isRecord(body) || !Array.isArray(body["order"])) {
        throw new TypeError("route optimizer answered without an order");
      }

      const order = body["order"].map(String);
      const distance = optionalNumber(body["distanceMeters"]);
      const duration = optionalNumber(body["durationSeconds"]);

      return {
        order,
        ...(distance === undefined ? {} : { distanceMeters: distance }),
        ...(duration === undefined ? {} : { durationSeconds: duration }),
      };
    },
  };
}

export interface OptimizedStops extends RouteOptimization {
  /** `fallback` when the optimizer failed or answered an invalid order. */
  readonly source: "optimizer" | "fallback";
  /** Why the fallback ran. */
  readonly fallbackReason?: string;
}

function isPermutation(
  request: RouteRequest,
  order: readonly string[],
): boolean {
  const ids = new Set(request.stops.map((stop) => stop.id));

  return (
    order.length === request.stops.length &&
    new Set(order).size === order.length &&
    order.every((id) => ids.has(id))
  );
}

/**
 * Orders the stops with `optimizer` and never throws: a failing optimizer, or
 * one whose order drops, repeats or invents a stop, gives the nearest-neighbour
 * order with `source: "fallback"` and the reason.
 */
export async function optimizeStops(
  optimizer: RouteOptimizer,
  request: RouteRequest,
): Promise<OptimizedStops> {
  let reason: string;

  try {
    const answer = await routeOptimizerOf(optimizer).optimize(request);

    if (isPermutation(request, answer.order)) {
      return { ...answer, source: "optimizer" };
    }

    reason = `optimizer "${optimizer.name}" returned an order that is not the request's stops`;
  } catch (error) {
    reason = error instanceof Error ? error.message : String(error);
  }

  return {
    ...nearestNeighbour(request),
    source: "fallback",
    fallbackReason: reason,
  };
}

/** A home-care visit: a booking with a place and a length. */
export interface VisitStop extends RouteStop {
  readonly durationMinutes: number;
}

export interface VisitShift {
  readonly startsAt: Temporal.Instant;
  readonly endsAt: Temporal.Instant;
}

export interface PlanVisitsOptions {
  /** Default: `nearestNeighbourOptimizer()`. */
  readonly optimizer?: RouteOptimizer;
  readonly start?: RoutePoint;
  readonly end?: RoutePoint;
  /** Straight-line travel speed. Default 30 km/h. */
  readonly averageSpeedKmh?: number;
}

export interface PlannedVisit {
  readonly id: string;
  readonly arriveAt: Temporal.Instant;
  readonly leaveAt: Temporal.Instant;
  /** `false` when the visit ends after the shift does. */
  readonly withinShift: boolean;
}

export interface PlannedVisits {
  readonly optimization: OptimizedStops;
  readonly visits: readonly PlannedVisit[];
}

/**
 * Orders the visits of one caregiver's shift and walks the shift clock along
 * the order: travel at `averageSpeedKmh`, then the visit's length. Visits that
 * end after the shift stay in the list with `withinShift: false`, so a planner
 * can move them to another shift.
 */
export async function planVisits(
  shift: VisitShift,
  stops: readonly VisitStop[],
  options: PlanVisitsOptions = {},
): Promise<PlannedVisits> {
  const request: RouteRequest = {
    stops,
    ...(options.start === undefined ? {} : { start: options.start }),
    ...(options.end === undefined ? {} : { end: options.end }),
  };

  const optimization = await optimizeStops(
    options.optimizer ?? nearestNeighbourOptimizer(),
    request,
  );

  const metersPerSecond = ((options.averageSpeedKmh ?? 30) * 1000) / 3600;
  const byId = new Map(stops.map((stop) => [stop.id, stop]));
  const visits: PlannedVisit[] = [];
  let clock = shift.startsAt;
  let previous = options.start;

  for (const id of optimization.order) {
    // SAFETY: the order is a permutation of the request's stops.
    const stop = byId.get(id)!;

    const travel =
      previous === undefined
        ? 0
        : Math.round(distanceMeters(previous, stop.point) / metersPerSecond);

    const arriveAt = clock.add({ seconds: travel });
    const leaveAt = arriveAt.add({ minutes: stop.durationMinutes });

    visits.push({
      id,
      arriveAt,
      leaveAt,
      withinShift: leaveAt.epochNanoseconds <= shift.endsAt.epochNanoseconds,
    });
    clock = leaveAt;
    previous = stop.point;
  }

  return { optimization, visits };
}
