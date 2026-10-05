/// <reference lib="esnext.temporal" />

// Keep this module free of imports: entries that only need the clock (events)
// must not pull in the error module.

/** The polyfill for runtimes without Temporal (Node 24, Safari, Hermes). */
export const TEMPORAL_POLYFILL = "temporal-polyfill/global";

export const TEMPORAL_MISSING: string = `Temporal is not available in this runtime. Pass it to defineSupabase(schema, { temporal }) (import { Temporal } from "temporal-polyfill"), or import "${TEMPORAL_POLYFILL}" once at startup.`;

let provided: typeof Temporal | undefined;

/**
 * Uses `namespace` wherever better-supabase needs Temporal, without touching
 * `globalThis`. `defineSupabase(schema, { temporal })` calls it; call it
 * yourself when you use a standalone helper (webhook verification, jobs)
 * without a definition. `undefined` goes back to the global.
 */
export function provideTemporal(namespace: typeof Temporal | undefined): void {
  provided = namespace;
}

/** The provided `Temporal`, else the runtime's, or `undefined` when neither exists. */
export function optionalTemporal(): typeof Temporal | undefined {
  if (provided !== undefined) return provided;
  const namespace: typeof Temporal | undefined = globalThis.Temporal;
  return namespace;
}

/**
 * The current instant, the default `now` everywhere. Without Temporal it
 * throws a `TypeError` that names the injection option and the polyfill.
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

function tagOf(value: unknown): unknown {
  if (typeof value !== "object" || value === null) return undefined;
  if (!(Symbol.toStringTag in value)) return undefined;
  return value[Symbol.toStringTag];
}

/**
 * The text Postgres reads back for a Temporal value: ISO 8601, with a
 * `ZonedDateTime` sent as its instant because Postgres rejects the
 * `[Region/City]` annotation. `undefined` for anything else.
 *
 * Values are recognized by `Symbol.toStringTag`, not `instanceof`, so values
 * from another realm or a second copy of the polyfill still encode.
 */
export function temporalText(value: unknown): string | undefined {
  const tag = tagOf(value);
  if (tag === undefined) return undefined;
  if (ISO_TAGS.has(tag)) return String(value);
  return tag === "Temporal.ZonedDateTime" &&
    typeof value === "object" &&
    value !== null &&
    isZoned(value)
    ? String(value.toInstant())
    : undefined;
}

interface ZonedLike {
  toInstant(): unknown;
}

function isZoned(value: object): value is ZonedLike {
  return "toInstant" in value && typeof value.toInstant === "function";
}

/** A `Temporal.Instant` from any copy of Temporal, checked by `Symbol.toStringTag`. */
export function isInstant(value: unknown): value is Temporal.Instant {
  return tagOf(value) === "Temporal.Instant";
}

/** A `Temporal.PlainDateTime` from any copy of Temporal. */
export function isPlainDateTime(
  value: unknown,
): value is Temporal.PlainDateTime {
  return tagOf(value) === "Temporal.PlainDateTime";
}

/** A `Temporal.PlainDate` from any copy of Temporal. */
export function isPlainDate(value: unknown): value is Temporal.PlainDate {
  return tagOf(value) === "Temporal.PlainDate";
}

/** A `Temporal.PlainTime` from any copy of Temporal. */
export function isPlainTime(value: unknown): value is Temporal.PlainTime {
  return tagOf(value) === "Temporal.PlainTime";
}

/** A `Temporal.ZonedDateTime` from any copy of Temporal. */
export function isZonedDateTime(
  value: unknown,
): value is Temporal.ZonedDateTime {
  return tagOf(value) === "Temporal.ZonedDateTime";
}
