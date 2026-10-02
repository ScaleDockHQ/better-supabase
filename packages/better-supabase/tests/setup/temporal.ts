import "temporal-polyfill/global";
import { expect } from "vitest";

const temporalTypes = [
  Temporal.Instant,
  Temporal.ZonedDateTime,
  Temporal.PlainDateTime,
  Temporal.PlainDate,
  Temporal.PlainTime,
  Temporal.Duration,
];

// Temporal objects keep their state in internal slots, so the default deep
// equality sees two empty objects and calls any two of them equal.
expect.addEqualityTesters([
  function temporalEquals(a, b) {
    const type = temporalTypes.find(
      (candidate) => a instanceof candidate || b instanceof candidate,
    );
    if (type === undefined) return;
    return a instanceof type && b instanceof type && String(a) === String(b);
  },
]);
