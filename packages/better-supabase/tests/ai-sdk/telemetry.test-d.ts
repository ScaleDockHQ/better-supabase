import type { Telemetry } from "ai";

import { describe, expectTypeOf, it } from "vitest";

import type {
  MeterTelemetryOptions,
  TelemetryStart,
} from "../../src/ai-sdk/telemetry.ts";

import { meterTelemetry } from "../../src/ai-sdk/telemetry.ts";

describe("meterTelemetry types", () => {
  it("returns an AI SDK 7 Telemetry integration", () => {
    expectTypeOf(meterTelemetry).returns.toEqualTypeOf<Telemetry>();
  });

  it("resolves the tenant from the start event", () => {
    expectTypeOf<MeterTelemetryOptions["tenant"]>().toEqualTypeOf<
      ((event: TelemetryStart) => string | undefined) | undefined
    >();

    expectTypeOf<TelemetryStart["runtimeContext"]>().toEqualTypeOf<unknown>();
  });
});
