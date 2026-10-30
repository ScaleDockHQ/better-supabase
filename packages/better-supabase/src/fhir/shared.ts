import type { ValidationIssue } from "../core/errors.ts";
import type { Result } from "../core/result.ts";
import type {
  FhirAnnotation,
  FhirCodeableConcept,
  FhirIdentifier,
  FhirReference,
} from "./types.ts";

import { dbError } from "../core/errors.ts";
import { err, ok } from "../core/result.ts";
import { temporalMissing } from "../core/temporal-required.ts";
import { optionalTemporal } from "../core/temporal.ts";

export const UCUM = "http://unitsofmeasure.org";

/** Maps a user id to a FHIR reference, such as a `Practitioner`. */
export type FhirUserReference = (userId: string) => FhirReference | undefined;

/** Options of the mappers whose resource points at a record. */
export interface FhirSubjectOptions {
  /** The record the resource is about. Default `Patient/<subjectId>`. */
  readonly subject?: FhirReference;
  /**
   * Maps the block's user ids (performer, author, owner) to references. Left
   * out, the resources carry no user references.
   */
  readonly user?: FhirUserReference;
}

export const patientReference = (id: string): FhirReference => ({
  reference: `Patient/${id}`,
});

export const subjectOf = (
  options: FhirSubjectOptions | undefined,
  subjectId: string,
): FhirReference => options?.subject ?? patientReference(subjectId);

export const userOf = (
  options: FhirSubjectOptions | undefined,
  userId: string | undefined,
): FhirReference | undefined =>
  userId === undefined ? undefined : options?.user?.(userId);

/** `T` where an optional key may also hold `undefined`. */
export type Loose<T> = {
  [K in keyof T]: Record<never, never> extends Pick<T, K>
    ? T[K] | undefined
    : T[K];
};

/** Drops the keys whose value is `undefined`, so the JSON stays minimal. */
export function compact<T extends object>(value: Loose<T>): T {
  // SAFETY: only optional keys may hold `undefined`, and those are removed.
  return Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  ) as T;
}

/** FHIR JSON never holds an empty array. */
export const nonEmpty = <T>(list: readonly T[]): readonly T[] | undefined =>
  list.length === 0 ? undefined : list;

export const text = (
  value: string | undefined,
): FhirCodeableConcept | undefined =>
  value === undefined ? undefined : { text: value };

export const notes = (
  value: string | undefined,
): readonly FhirAnnotation[] | undefined =>
  value === undefined ? undefined : [{ text: value }];

export const identifiers = (
  value: string | undefined,
  system: string | undefined,
): readonly FhirIdentifier[] | undefined =>
  value === undefined
    ? undefined
    : [compact<FhirIdentifier>({ system, value })];

/**
 * A `Temporal.Instant` (a FHIR `instant` or `dateTime`), a `Temporal.PlainDate`
 * (a FHIR `date`), or a string already in FHIR form.
 */
export type FhirTemporal = Temporal.Instant | Temporal.PlainDate | string;

export const fhirTime = (value: FhirTemporal | undefined): string | undefined =>
  value?.toString();

/** The id after the last `/` of a relative reference such as `Patient/42`. */
export function referenceId(
  reference: Untrusted<FhirReference>,
): string | undefined {
  const value = reference.reference;

  if (typeof value !== "string" || value.startsWith("#")) {
    return undefined;
  }

  const id = value.split("/").at(-1);

  return id === undefined || id === "" ? undefined : id;
}

/** Collects the problems of one import. */
export class Issues {
  readonly list: ValidationIssue[] = [];

  add(path: readonly PropertyKey[], message: string): void {
    this.list.push({ path, message });
  }

  /** The value, after noting `message` when it is missing. */
  required<T>(
    value: T | undefined,
    path: readonly PropertyKey[],
    message: string,
  ): T | undefined {
    if (value === undefined) {
      this.add(path, message);
    }

    return value;
  }

  get empty(): boolean {
    return this.list.length === 0;
  }

  failure(resource: string): Result<never> {
    const first = this.list[0]?.message ?? "a required element is missing";

    return err(
      dbError("validation", `The ${resource} can't be imported: ${first}`, {
        issues: this.list,
      }),
    );
  }
}

/**
 * Builds an import with the runtime's `Temporal`, or the error naming the
 * polyfill.
 */
export function withTemporal<T>(
  build: (time: typeof Temporal) => T,
): Result<T> {
  const time = optionalTemporal();

  return time === undefined ? err(temporalMissing()) : ok(build(time));
}

export const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Untrusted JSON read through T's keys, each `unknown` until checked. */
export type Untrusted<T> = { readonly [K in keyof T]?: unknown };

export const fieldsOf = <T>(value: unknown): Untrusted<T> =>
  isObject(value) ? value : {};

export const itemsOf = <T>(value: unknown): Untrusted<T>[] =>
  Array.isArray(value) ? value.filter(isObject) : [];

const FHIR_DATE = /^\d{4}-\d{2}-\d{2}/;

/** A FHIR `date` or `dateTime`, as the calendar date it starts with. */
export function plainDateOf(
  value: unknown,
  path: readonly PropertyKey[],
  issues: Issues,
): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "string" || !FHIR_DATE.test(value)) {
    issues.add(path, `${path.join(".")} must be a full date`);

    return;
  }

  return value.slice(0, 10);
}

const FHIR_INSTANT =
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;

/** A FHIR `dateTime` with a time and an offset, as an instant string. */
export function instantOf(
  value: unknown,
  path: readonly PropertyKey[],
  issues: Issues,
): string | undefined {
  if (typeof value !== "string" || !FHIR_INSTANT.test(value)) {
    issues.add(
      path,
      `${path.join(".")} must be a dateTime with a time and a time zone`,
    );

    return;
  }

  return value;
}
