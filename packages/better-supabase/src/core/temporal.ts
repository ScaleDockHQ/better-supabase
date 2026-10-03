/// <reference lib="esnext.temporal" />

// Keep this module free of imports: entries that only need the clock (events)
// must not pull in the error module.

/** The polyfill for runtimes without Temporal (Node 24, Safari). */
export const TEMPORAL_POLYFILL = "temporal-polyfill/global";

export const TEMPORAL_MISSING: string = `Temporal is not available in this runtime. Import "${TEMPORAL_POLYFILL}" once at startup.`;

/** The runtime's `Temporal`, or `undefined` before the polyfill loads. */
export function optionalTemporal(): typeof Temporal | undefined {
  const namespace: typeof Temporal | undefined = globalThis.Temporal;
  return namespace;
}

/**
 * The current instant, the default `now` everywhere. Without Temporal it
 * throws a `TypeError` that names the polyfill.
 */
export function nowInstant(): Temporal.Instant {
  const namespace = optionalTemporal();
  if (namespace === undefined) throw new TypeError(TEMPORAL_MISSING);
  return namespace.Now.instant();
}

const ISO_TAGS: ReadonlySet<unknown> = new Set([
  "Temporal.Instant",
  "Temporal.PlainDateTime",
  "Temporal.PlainDate",
  "Temporal.PlainTime",
]);

/**
 * The text Postgres reads back for a Temporal value: ISO 8601, with a
 * `ZonedDateTime` sent as its instant because Postgres rejects the
 * `[Region/City]` annotation. `undefined` for anything else.
 *
 * Values are recognized by `Symbol.toStringTag`, not `instanceof`, so values
 * from another realm or a second copy of the polyfill still encode.
 */
export function temporalText(value: unknown): string | undefined {
  if (typeof value !== "object" || value === null) return undefined;
  if (!(Symbol.toStringTag in value)) return undefined;
  const tag = value[Symbol.toStringTag];
  if (ISO_TAGS.has(tag)) return String(value);
  return tag === "Temporal.ZonedDateTime" && isZoned(value)
    ? String(value.toInstant())
    : undefined;
}

interface ZonedLike {
  toInstant(): unknown;
}

function isZoned(value: object): value is ZonedLike {
  return "toInstant" in value && typeof value.toInstant === "function";
}
