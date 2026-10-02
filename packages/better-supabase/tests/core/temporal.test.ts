import { describe, expect, it, onTestFinished, vi } from "vitest";

import {
  nowInstant,
  optionalTemporal,
  TEMPORAL_POLYFILL,
  temporalText,
} from "../../src/core/temporal.ts";

const withoutTemporal = () => {
  vi.stubGlobal("Temporal", undefined);
  onTestFinished(() => {
    vi.unstubAllGlobals();
  });
};

describe("temporal", () => {
  it("returns the runtime's Temporal", () => {
    expect(optionalTemporal()).toBe(globalThis.Temporal);
  });

  it("names the polyfill when Temporal is missing", () => {
    withoutTemporal();
    expect(optionalTemporal()).toBeUndefined();
    expect(() => nowInstant()).toThrow(TypeError);
    expect(() => nowInstant()).toThrow(TEMPORAL_POLYFILL);
  });

  it("reads the current instant from the system clock", () => {
    const now = Temporal.Instant.from("2026-10-02T08:00:00Z");
    vi.useFakeTimers({ now: now.epochMilliseconds });
    onTestFinished(() => {
      vi.useRealTimers();
    });
    expect(nowInstant()).toEqual(now);
  });
});

describe("temporalText", () => {
  it.each<[string, unknown, string | undefined]>([
    [
      "an Instant",
      Temporal.Instant.from("2026-01-02T00:00:00Z"),
      "2026-01-02T00:00:00Z",
    ],
    [
      "a ZonedDateTime, as its instant",
      Temporal.ZonedDateTime.from(
        "2026-07-01T02:00:00+02:00[Europe/Amsterdam]",
      ),
      "2026-07-01T00:00:00Z",
    ],
    [
      "a PlainDateTime",
      Temporal.PlainDateTime.from("2026-01-02T10:30"),
      "2026-01-02T10:30:00",
    ],
    ["a PlainDate", Temporal.PlainDate.from("2026-01-02"), "2026-01-02"],
    ["a PlainTime", Temporal.PlainTime.from("10:30"), "10:30:00"],
    ["a Duration", Temporal.Duration.from({ hours: 1 }), undefined],
    ["a string", "2026-01-02", undefined],
  ])("formats %s", (_name, value, expected) => {
    expect(temporalText(value)).toBe(expected);
  });

  it("formats nothing without Temporal", () => {
    const instant = Temporal.Instant.fromEpochMilliseconds(0);
    withoutTemporal();
    expect(temporalText(instant)).toBeUndefined();
  });
});
