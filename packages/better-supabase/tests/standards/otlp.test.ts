import { describe, expect, it } from "vitest";

import { otlpLogs } from "../../src/blocks/webhooks/index.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe(`OTLP/HTTP logs, JSON encoding (OTLP ${SPEC_PINS.otlp})`, () => {
  it("writes an ExportLogsServiceRequest with lowerCamelCase fields and string int64s", async () => {
    const encoded = await otlpLogs().encode(
      [
        {
          specversion: "1.0",
          id: "evt-1",
          source: "urn:test",
          type: "user.signed_in",
          time: "2026-01-01T00:00:00Z",
          data: { count: 3 },
        },
      ],
      {
        url: "https://collector.example.com/v1/logs",
        batch: true,
        tenant: null,
      },
    );
    expect(encoded.headers["content-type"]).toBe("application/json");
    const request = JSON.parse(encoded.body);
    const record = request.resourceLogs[0].scopeLogs[0].logRecords[0];
    expect(Object.keys(record).toSorted()).toEqual([
      "attributes",
      "body",
      "eventName",
      "observedTimeUnixNano",
      "severityNumber",
      "severityText",
      "timeUnixNano",
    ]);
    expect(record.timeUnixNano).toBe("1767225600000000000");
    expect(record.body).toEqual({
      kvlistValue: { values: [{ key: "count", value: { intValue: "3" } }] },
    });
  });

  it("treats a partial success as delivered and keeps the rejection", () => {
    expect(
      otlpLogs().classify?.({
        status: 200,
        body: JSON.stringify({ partialSuccess: { rejectedLogRecords: "1" } }),
      }),
    ).toMatchObject({ outcome: "succeeded" });
  });
});
