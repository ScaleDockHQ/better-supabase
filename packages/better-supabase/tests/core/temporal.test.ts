import { Temporal as Polyfill } from "temporal-polyfill";
import { describe, expect, it, onTestFinished, vi } from "vitest";

import { defineSupabase } from "../../src/core/define.ts";
import {
  isInstant,
  isPlainDate,
  isPlainDateTime,
  isPlainTime,
  isZonedDateTime,
  nowInstant,
  optionalTemporal,
  provideTemporal,
  TEMPORAL_POLYFILL,
  temporalText,
} from "../../src/core/temporal.ts";
import { schema } from "../fixtures/generated.ts";

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

  it("prefers a provided namespace over the global, without touching globalThis", () => {
    withoutTemporal();
    provideTemporal(Polyfill);
    onTestFinished(() => {
      provideTemporal(undefined);
    });
    expect(optionalTemporal()).toBe(Polyfill);
    expect(nowInstant()).toBeInstanceOf(Polyfill.Instant);
    expect(globalThis.Temporal).toBeUndefined();
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

describe("defineSupabase({ temporal })", () => {
  it("uses the injected namespace when the runtime has none", () => {
    withoutTemporal();
    onTestFinished(() => {
      provideTemporal(undefined);
    });
    const betterSupabase = defineSupabase(schema, { temporal: Polyfill });
    expect(betterSupabase.temporal).toBe(Polyfill);
    expect(optionalTemporal()).toBe(Polyfill);
  });

  it("falls back to the global", () => {
    expect(defineSupabase(schema).temporal).toBe(globalThis.Temporal);
  });
});

describe("guards", () => {
  it("recognize values from any Temporal copy by their tag", () => {
    const instant = Polyfill.Instant.fromEpochMilliseconds(0);
    withoutTemporal();
    expect(isInstant(instant)).toBe(true);
    expect(isInstant("1970-01-01T00:00:00Z")).toBe(false);
    expect(isInstant(null)).toBe(false);
    expect(
      isPlainDateTime(Polyfill.PlainDateTime.from("2026-01-02T10:30")),
    ).toBe(true);
    expect(isPlainDate(Polyfill.PlainDate.from("2026-01-02"))).toBe(true);
    expect(isPlainTime(Polyfill.PlainTime.from("10:30"))).toBe(true);
    expect(
      isZonedDateTime(instant.toZonedDateTimeISO("Europe/Amsterdam")),
    ).toBe(true);
    expect(isPlainDate(instant)).toBe(false);
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

  it("formats values from another Temporal copy by their tag", () => {
    const instant = Temporal.Instant.fromEpochMilliseconds(0);
    withoutTemporal();
    expect(temporalText(instant)).toBe("1970-01-01T00:00:00Z");
    expect(
      temporalText({
        [Symbol.toStringTag]: "Temporal.PlainDate",
        toString: () => "2026-01-02",
      }),
    ).toBe("2026-01-02");
    expect(
      temporalText({
        [Symbol.toStringTag]: "Temporal.ZonedDateTime",
        toInstant: () => instant,
      }),
    ).toBe("1970-01-01T00:00:00Z");
    expect(
      temporalText({ [Symbol.toStringTag]: "Temporal.ZonedDateTime" }),
    ).toBeUndefined();
  });
});
