import type { AnySection } from "../blocks/sections.ts";
import type { AsyncResult } from "../core/result.ts";
import type { SubjectRef } from "../schema/types.ts";
import type { ConformanceReport } from "./conformance.ts";

import { subjectKey } from "../core/block-subjects.ts";
import { conform, expect } from "./conformance.ts";

export interface TestSectionOptions {
  /** The block client the section reads through, such as a fake. */
  readonly client: unknown;
  /** A record the client holds rows for. */
  readonly subject: SubjectRef;
  /** Records to count, for a section with `count`. Default: `[subject]`. */
  readonly subjects?: readonly SubjectRef[];
}

const callable = (value: unknown): boolean => typeof value === "function";

/**
 * Runs the `defineSection` contract against `section`: the API version, a read
 * permission, the event patterns, a `load` that settles, and a `count` keyed by
 * `subjectKey` with a whole number per record. Throws a `ConformanceError`
 * listing every failed check.
 */
export function testSection(
  name: string,
  section: AnySection,
  options: TestSectionOptions,
): Promise<ConformanceReport> {
  const subjects = options.subjects ?? [options.subject];

  // SAFETY: a section's functions take the client its block's creator made,
  // which the test passes.
  const load = section.load as (
    client: unknown,
    subject: SubjectRef,
    options: unknown,
  ) => AsyncResult<unknown>;

  // SAFETY: as for `load`.
  const count = section.count as
    | ((
        client: unknown,
        subjects: readonly SubjectRef[],
      ) => AsyncResult<Readonly<Record<string, number>>>)
    | undefined;

  return conform(`Section "${name}"`, [
    [
      "has apiVersion 1",
      () => {
        const version: unknown = section.apiVersion;
        expect(version === 1, "apiVersion must be 1");
      },
    ],
    [
      "names a read permission",
      () => {
        expect(
          typeof section.permissions.read === "string" &&
            section.permissions.read.length > 0,
          "permissions.read must be a non-empty action name",
        );
      },
    ],
    [
      "lists event types",
      () => {
        expect(
          section.events.every(
            (event) => typeof event === "string" && event.length > 0,
          ),
          "events must be non-empty strings",
        );
      },
    ],
    [
      "loads a record",
      async () => {
        expect(callable(section.load), "load must be a function");

        const result = await load(options.client, options.subject, undefined);
        expect(result.ok, "load must succeed for a record the client holds");
      },
    ],
    count !== undefined && [
      "counts records by subject key",
      async () => {
        const result = await count(options.client, subjects);
        expect(result.ok, "count must succeed");

        const wanted = new Set(subjects.map((subject) => subjectKey(subject)));

        for (const [key, value] of Object.entries(result.data)) {
          expect(
            wanted.has(key),
            `count returned "${key}", not a type:id key asked for`,
          );
          expect(
            Number.isInteger(value) && value >= 0,
            `count for "${key}" must be a whole number`,
          );
        }
      },
    ],
  ]);
}
