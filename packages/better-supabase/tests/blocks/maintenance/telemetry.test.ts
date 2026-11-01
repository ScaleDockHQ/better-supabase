import { describe, expect, it, vi } from "vitest";

import {
  createTelemetryHandler,
  ingestTelemetry,
  parseOtlpMetrics,
  parseTelemetryPoints,
} from "../../../src/blocks/maintenance/telemetry.ts";
import { dbError } from "../../../src/core/errors.ts";
import { err, ok } from "../../../src/core/result.ts";

const meterFor = (device: string, metric: string): string | undefined =>
  device === "pump-1" && metric === "run_hours" ? "m-1" : undefined;

function maintenance() {
  const recordReading = vi.fn(async (meterId: string) =>
    meterId === "m-bad"
      ? err(dbError("raised", "lower", { hint: "MAINTENANCE_METER_LOWER" }))
      : ok({ id: meterId }),
  );

  return { recordReading, client: { recordReading } as never };
}

describe("parseTelemetryPoints", () => {
  it("reads ISO and epoch times", () => {
    const result = parseTelemetryPoints({
      points: [
        {
          device: "pump-1",
          metric: "run_hours",
          value: 10.5,
          time: "2026-10-01T10:00:00Z",
        },
        {
          device: "pump-1",
          metric: "run_hours",
          value: 11,
          time: 1_790_000_000_000,
        },
      ],
    });

    expect(result.ok && result.data).toHaveLength(2);
  });

  it.each([
    [{}],
    [{ points: [{ device: "d", metric: "m", value: "1", time: 1 }] }],
    [{ points: [{ device: "d", metric: "m", value: 1, time: "nope" }] }],
    [{ points: [{ device: "", metric: "m", value: 1, time: 1 }] }],
  ])("refuses a bad batch %#", (body) => {
    expect(parseTelemetryPoints(body).ok).toBe(false);
  });

  it("limits the batch size", () => {
    const points = Array.from({ length: 3 }, () => ({
      device: "d",
      metric: "m",
      value: 1,
      time: 1,
    }));

    expect(parseTelemetryPoints({ points }, 2).ok).toBe(false);
  });
});

describe("parseOtlpMetrics", () => {
  it("reads gauge and sum points and skips resources without a device", () => {
    const points = parseOtlpMetrics({
      resourceMetrics: [
        {
          resource: {
            attributes: [
              { key: "device.id", value: { stringValue: "pump-1" } },
            ],
          },
          scopeMetrics: [
            {
              metrics: [
                {
                  name: "run_hours",
                  gauge: {
                    dataPoints: [
                      { asDouble: 12.5, timeUnixNano: "1790000000000000000" },
                    ],
                  },
                },
                {
                  name: "cycles",
                  sum: {
                    dataPoints: [
                      { asInt: "7", timeUnixNano: "1790000001000000000" },
                    ],
                  },
                },
                { name: "latency", histogram: { dataPoints: [{}] } },
              ],
            },
          ],
        },
        { resource: { attributes: [] }, scopeMetrics: [] },
      ],
    });

    expect(points).toHaveLength(2);
    expect(points[0]).toMatchObject({
      device: "pump-1",
      metric: "run_hours",
      value: 12.5,
    });
    expect(points[0]?.at.getTime()).toBe(1_790_000_000_000);
    expect(points[1]?.value).toBe(7);
  });
});

describe("ingestTelemetry", () => {
  const at = new Date("2026-10-01T10:00:00Z");

  it("writes the highest reading per meter once", async () => {
    const { recordReading, client } = maintenance();

    const summary = await ingestTelemetry({ maintenance: client, meterFor }, [
      { device: "pump-1", metric: "run_hours", value: 10, at },
      { device: "pump-1", metric: "run_hours", value: 12.25, at },
      { device: "pump-1", metric: "run_hours", value: 11, at },
      { device: "fan-2", metric: "rpm", value: 5, at },
    ]);

    expect(summary).toMatchObject({
      accepted: 3,
      unmapped: 1,
      updated: ["m-1"],
      failures: [],
    });
    expect(recordReading).toHaveBeenCalledOnce();
    expect((recordReading.mock.calls[0] as unknown[] | undefined)?.[1]).toBe(
      "12.25",
    );
  });

  it("ignores negative values and reports failing meters without stopping", async () => {
    const { client } = maintenance();

    const summary = await ingestTelemetry(
      {
        maintenance: client,
        meterFor: (device) => (device === "a" ? "m-bad" : "m-ok"),
      },
      [
        { device: "a", metric: "x", value: 1, at },
        { device: "b", metric: "x", value: -4, at },
        { device: "c", metric: "x", value: 2e-7, at },
      ],
    );

    expect(summary.failures.map((failure) => failure.meterId)).toEqual([
      "m-bad",
    ]);
    expect(summary.updated).toEqual(["m-ok"]);
  });
});

describe("createTelemetryHandler", () => {
  const request = (
    body: unknown,
    headers: Record<string, string> = {},
  ): Request =>
    new Request("https://app.example/telemetry", {
      method: "POST",
      headers,
      body: typeof body === "string" ? body : JSON.stringify(body),
    });

  it("checks the caller before the body", async () => {
    const { client } = maintenance();

    const handle = createTelemetryHandler({
      maintenance: client,
      meterFor,
      authorize: async (req) => req.headers.get("x-key") === "k",
    });

    expect((await handle(request({}))).status).toBe(401);
    expect((await handle(new Request("https://app.example/t"))).status).toBe(
      405,
    );
    expect((await handle(request("{", { "x-key": "k" }))).status).toBe(400);
    expect(
      (await handle(request({ points: "x" }, { "x-key": "k" }))).status,
    ).toBe(400);
  });

  it("accepts a batch and reports the summary", async () => {
    const { client } = maintenance();

    const handle = createTelemetryHandler({
      maintenance: client,
      meterFor,
      authorize: async () => true,
    });

    const response = await handle(
      request({
        points: [
          {
            device: "pump-1",
            metric: "run_hours",
            value: 3,
            time: 1_790_000_000_000,
          },
        ],
      }),
    );

    expect(response.status).toBe(202);
    expect(await response.json()).toMatchObject({
      accepted: 1,
      updated: ["m-1"],
    });
  });

  it("limits the body size", async () => {
    const { client } = maintenance();

    const handle = createTelemetryHandler({
      maintenance: client,
      meterFor,
      authorize: async () => true,
      maxBytes: 10,
    });

    expect((await handle(request({ points: [] }))).status).toBe(413);
  });
});
