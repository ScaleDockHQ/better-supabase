import { describe, expect, it } from "vitest";

import { expandRule } from "../../src/blocks/reminders/rrule.ts";
import { SPEC_PINS } from "../../src/core/spec-pins.ts";

describe("RFC 5545", () => {
  it("pins the recurrence rule version", () => {
    expect(SPEC_PINS.rfc5545).toBe("2009-09");
  });

  it("expands the daily count example", () => {
    const found = expandRule({
      dtstart: Temporal.Instant.from("1997-09-02T09:00:00Z").toZonedDateTimeISO(
        "UTC",
      ),
      rrule: "FREQ=DAILY;COUNT=3",
    });
    expect(found.map((item) => item.toPlainDate().toString())).toEqual([
      "1997-09-02",
      "1997-09-03",
      "1997-09-04",
    ]);
  });
});
