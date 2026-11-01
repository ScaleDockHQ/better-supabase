import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { Maintenance } from "./maintenance.ts";

import { dbError } from "../../core/errors.ts";
import { isRecord } from "../../core/guards.ts";
import { err, ok } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";

/** One reading from a device. */
export interface TelemetryPoint {
  /** The device's id, such as an asset id or a serial number. */
  readonly device: string;
  /** The metric's name, such as `run_hours`. */
  readonly metric: string;
  readonly value: number;
  readonly at: Date;
}

/**
 * Reads the plain JSON batch a gateway posts: `{ "points": [{ "device",
 * "metric", "value", "time" }] }`, where `time` is an ISO 8601 string or epoch
 * milliseconds. A point that is not valid fails the whole batch, so a gateway
 * never believes a partly stored batch was fine.
 */
export function parseTelemetryPoints(
  body: unknown,
  limit = 1000,
): Result<readonly TelemetryPoint[]> {
  const list = isRecord(body) ? body["points"] : undefined;

  if (!Array.isArray(list)) {
    return err(dbError("invalid_input", "The batch has no points list"));
  }

  if (list.length > limit) {
    return err(
      dbError("invalid_input", `A batch holds at most ${limit} points`),
    );
  }

  const points: TelemetryPoint[] = [];

  for (const [index, item] of list.entries()) {
    const device = isRecord(item) ? item["device"] : undefined;
    const metric = isRecord(item) ? item["metric"] : undefined;
    const value = isRecord(item) ? item["value"] : undefined;
    const time = isRecord(item) ? item["time"] : undefined;

    const at =
      typeof time === "string" || typeof time === "number"
        ? new Date(time)
        : undefined;

    if (
      typeof device !== "string" ||
      device === "" ||
      typeof metric !== "string" ||
      metric === "" ||
      typeof value !== "number" ||
      !Number.isFinite(value) ||
      at === undefined ||
      Number.isNaN(at.getTime())
    ) {
      return err(
        dbError("invalid_input", `Point ${index} is not a valid reading`),
      );
    }

    points.push({ device, metric, value, at });
  }

  return ok(points);
}

function otlpAttribute(
  attributes: unknown,
  keys: readonly string[],
): string | undefined {
  for (const attribute of Array.isArray(attributes) ? attributes : []) {
    if (
      isRecord(attribute) &&
      typeof attribute["key"] === "string" &&
      keys.includes(attribute["key"]) &&
      isRecord(attribute["value"]) &&
      typeof attribute["value"]["stringValue"] === "string"
    ) {
      return attribute["value"]["stringValue"];
    }
  }

  return undefined;
}

/**
 * Reads gauge and sum data points from an OTLP/HTTP JSON metrics export (OTLP
 * 1.7). The device is the resource attribute `device.id`, or else
 * `service.instance.id`; a resource with neither is skipped. Histograms are not
 * readings and are skipped too.
 */
export function parseOtlpMetrics(body: unknown): readonly TelemetryPoint[] {
  const points: TelemetryPoint[] = [];
  const resources = isRecord(body) ? body["resourceMetrics"] : undefined;

  for (const resource of Array.isArray(resources) ? resources : []) {
    const device = otlpAttribute(
      isRecord(resource) && isRecord(resource["resource"])
        ? resource["resource"]["attributes"]
        : undefined,
      ["device.id", "service.instance.id"],
    );

    if (device === undefined || !isRecord(resource)) {
      continue;
    }

    for (const scope of Array.isArray(resource["scopeMetrics"])
      ? resource["scopeMetrics"]
      : []) {
      for (const metric of isRecord(scope) && Array.isArray(scope["metrics"])
        ? scope["metrics"]
        : []) {
        const data = isRecord(metric)
          ? (metric["gauge"] ?? metric["sum"])
          : undefined;

        if (
          !isRecord(metric) ||
          typeof metric["name"] !== "string" ||
          !isRecord(data) ||
          !Array.isArray(data["dataPoints"])
        ) {
          continue;
        }

        for (const point of data["dataPoints"]) {
          if (!isRecord(point)) {
            continue;
          }

          // OTLP JSON writes 64-bit integers as strings.
          const raw = point["asDouble"] ?? point["asInt"];
          const value = typeof raw === "string" ? Number(raw) : raw;
          const nanos = point["timeUnixNano"];

          const millis =
            typeof nanos === "string" || typeof nanos === "number"
              ? Number(BigInt(nanos) / 1_000_000n)
              : undefined;

          if (
            typeof value === "number" &&
            Number.isFinite(value) &&
            millis !== undefined
          ) {
            points.push({
              device,
              metric: metric["name"],
              value,
              at: new Date(millis),
            });
          }
        }
      }
    }
  }

  return points;
}

/** A failed meter update in a summary. */
export interface TelemetryFailure {
  readonly meterId: string;
  readonly error: DbError;
}

export interface TelemetrySummary {
  /** Points that mapped to a meter. */
  readonly accepted: number;
  /** Points `meterFor` returned no meter for. */
  readonly unmapped: number;
  /** Meters whose reading was written. */
  readonly updated: readonly string[];
  readonly failures: readonly TelemetryFailure[];
}

export interface TelemetryIngestOptions {
  readonly maintenance: Pick<Maintenance, "recordReading">;
  /**
   * The meter a device's metric feeds, or `undefined` to ignore the point. Look
   * the id up from your own table, or from `listMeters` (a meter's `assetId`
   * ties it to an asset).
   */
  readonly meterFor: (device: string, metric: string) => string | undefined;
}

function decimal(value: number): string {
  const text = String(value);

  return text.includes("e") ? value.toFixed(6) : text;
}

/**
 * Writes a batch as meter readings. A meter counts up, so the point with the
 * highest value per meter wins, at its own time; lower or repeated points of
 * the same batch change nothing. A meter whose stored reading is higher than
 * the batch's refuses it as `recordReading` does, and the summary lists it
 * under `failures` without stopping the others. Negative values are refused.
 */
export async function ingestTelemetry(
  options: TelemetryIngestOptions,
  points: readonly TelemetryPoint[],
): Promise<TelemetrySummary> {
  const best = new Map<string, TelemetryPoint>();
  let unmapped = 0;
  let accepted = 0;

  for (const point of points) {
    const meterId = options.meterFor(point.device, point.metric);

    if (meterId === undefined) {
      unmapped += 1;
      continue;
    }

    accepted += 1;

    const current = best.get(meterId);

    if (
      point.value >= 0 &&
      (current === undefined || point.value > current.value)
    ) {
      best.set(meterId, point);
    }
  }

  const updated: string[] = [];
  const failures: TelemetryFailure[] = [];

  for (const [meterId, point] of best) {
    const result = await options.maintenance.recordReading(
      meterId,
      decimal(point.value),
      temporal().Instant.fromEpochMilliseconds(point.at.getTime()),
    );

    if (result.ok) {
      updated.push(meterId);
    } else {
      failures.push({ meterId, error: result.error });
    }
  }

  return { accepted, unmapped, updated, failures };
}

export interface TelemetryHandlerOptions extends TelemetryIngestOptions {
  /**
   * Checks the caller before the body is read, such as a device token or a
   * signature. There is no default: an ingest endpoint writes to your
   * maintenance data and must not be open.
   */
  readonly authorize: (request: Request) => Promise<boolean>;
  /** `points` (default) for the gateway JSON, or `otlp` for OTLP/HTTP JSON. */
  readonly format?: "points" | "otlp";
  /** Largest body, in bytes. Default 1,000,000. */
  readonly maxBytes?: number;
}

function json(status: number, body: unknown): Response {
  return Response.json(body, { status });
}

/**
 * A Fetch handler for `POST` telemetry. It answers 401 before reading the body,
 * 413 for a large body, 400 for a batch that is not valid and 202 with the
 * summary otherwise (a batch with some failed meters is still 202; the summary
 * lists them).
 */
export function createTelemetryHandler(
  options: TelemetryHandlerOptions,
): (request: Request) => Promise<Response> {
  const maxBytes = options.maxBytes ?? 1_000_000;

  return async (request) => {
    if (request.method !== "POST") {
      return json(405, { error: "method_not_allowed" });
    }

    if (!(await options.authorize(request))) {
      return json(401, { error: "unauthorized" });
    }

    const text = await request.text();

    if (new TextEncoder().encode(text).byteLength > maxBytes) {
      return json(413, { error: "too_large" });
    }

    let body: unknown;

    try {
      body = JSON.parse(text);
    } catch {
      return json(400, { error: "invalid_json" });
    }

    let points: readonly TelemetryPoint[];

    if (options.format === "otlp") {
      points = parseOtlpMetrics(body);
    } else {
      const parsed = parseTelemetryPoints(body);

      if (!parsed.ok) {
        return json(400, { error: parsed.error.message });
      }

      points = parsed.data;
    }

    const summary = await ingestTelemetry(options, points);

    return json(202, {
      accepted: summary.accepted,
      unmapped: summary.unmapped,
      updated: summary.updated,
      failures: summary.failures.map((failure) => ({
        meterId: failure.meterId,
        message: failure.error.message,
      })),
    });
  };
}
