import type { SubjectRef } from "../schema/types.ts";

import { textOf } from "./block-helpers.ts";
import { AsyncResult, ok } from "./result.ts";

/** A row's subject columns as a `SubjectRef`. */
export function subjectRefOf(type: unknown, id: unknown): SubjectRef {
  return { type: textOf(type), id: textOf(id) };
}

/** A row's subject columns as a `SubjectRef`, or `undefined` when unset. */
export function optionalSubjectRefOf(
  type: unknown,
  id: unknown,
): SubjectRef | undefined {
  return typeof type === "string" &&
    type !== "" &&
    (typeof id === "string" || typeof id === "number")
    ? { type, id: String(id) }
    : undefined;
}

/**
 * The ids of `subjects` grouped by type, in first-seen order and without
 * repeats, for functions that take one subject type and many ids.
 */
export function subjectIdsByType(
  subjects: readonly SubjectRef[],
): ReadonlyMap<string, readonly string[]> {
  const grouped = new Map<string, string[]>();

  for (const subject of subjects) {
    const ids = grouped.get(subject.type) ?? [];

    if (!ids.includes(subject.id)) {
      ids.push(subject.id);
    }

    grouped.set(subject.type, ids);
  }

  return grouped;
}

/** The map key of a subject in a batch result: `type:id`. */
export function subjectKey(subject: SubjectRef): string {
  return `${subject.type}:${subject.id}`;
}

/**
 * One call per subject type over `subjects`, the results merged into one record
 * keyed by `subjectKey` (`type:id`). The first error wins.
 */
export function bySubjectType<V>(
  subjects: readonly SubjectRef[],
  call: (
    type: string,
    ids: readonly string[],
  ) => AsyncResult<Readonly<Record<string, V>>>,
): AsyncResult<Readonly<Record<string, V>>> {
  return AsyncResult.from(async () => {
    const merged: Record<string, V> = {};
    const groups = [...subjectIdsByType(subjects)];

    const results = await Promise.all(
      groups.map(async ([type, ids]) => [type, await call(type, ids)] as const),
    );

    for (const [type, result] of results) {
      if (!result.ok) {
        return result;
      }

      for (const [id, value] of Object.entries(result.data)) {
        merged[subjectKey({ type, id })] = value;
      }
    }

    return ok(merged);
  });
}
