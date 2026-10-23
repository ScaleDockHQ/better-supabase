"use client";

import type { BlockEnv, RecordRef } from "better-supabase/blocks";
import type {
  ResolvedSubject,
  Subjects,
  SubjectsActions,
  SubjectsSnapshot,
} from "better-supabase/blocks/subjects";

import { envBlockOptions, subjectKey } from "better-supabase/blocks";
import {
  batchSubjects,
  createSubjects,
  createSubjectsController,
} from "better-supabase/blocks/subjects";
import { useBlockEnv, useController } from "better-supabase/react";

export type { ResolvedSubject } from "better-supabase/blocks/subjects";

const sources = new WeakMap<BlockEnv["supabase"], Subjects>();

/** One batched subjects client per supabase-js client, shared by its hooks. */
function sourceOf(env: BlockEnv): Subjects {
  let source = sources.get(env.supabase);

  if (source === undefined) {
    source = batchSubjects(createSubjects(envBlockOptions(env, "subjects")));
    sources.set(env.supabase, source);
  }

  return source;
}

export interface SubjectsState extends SubjectsSnapshot, SubjectsActions {
  /** The resolved subject of `ref`, or `undefined` while loading or unreadable. */
  readonly get: (ref: RecordRef) => ResolvedSubject | undefined;
}

/**
 * Titles and paths of `refs` from `config.records`. The hooks rendered in the
 * same tick share one `subject_titles` call, so a list of rows that each show a
 * subject link costs one round trip.
 *
 * ```tsx
 * const { get } = useSubjects(rows.map((row) => row.subject));
 * ```
 */
export function useSubjects(refs: readonly RecordRef[]): SubjectsState {
  const env = useBlockEnv();

  const key = [
    ...new Set(refs.map((ref) => JSON.stringify([ref.type, ref.id]))),
  ]
    .toSorted()
    .join("\n");

  const { view } = useController(
    () =>
      createSubjectsController({
        client: sourceOf(env),
        auth: env.auth,
        refs:
          key === ""
            ? []
            : key.split("\n").map((line): RecordRef => {
                // SAFETY: each line is the `[type, id]` pair written above.
                const [type, id] = JSON.parse(line) as [string, string];

                return { type, id };
              }),
      }),
    [env, key],
  );

  return { ...view, get: (ref) => view.subjects?.[subjectKey(ref)] };
}

export interface SubjectState {
  /** `undefined` while loading, `null` when the caller can't read it. */
  readonly subject: ResolvedSubject | null | undefined;
  readonly error: SubjectsSnapshot["error"];
  readonly refresh: SubjectsActions["refresh"];
}

/**
 * One subject's title and path, batched with the other `useSubject` and
 * `useSubjects` calls of the same render.
 */
export function useSubject(ref: RecordRef | null | undefined): SubjectState {
  const { subjects, error, get, refresh } = useSubjects(ref ? [ref] : []);

  return {
    subject:
      ref === null || ref === undefined
        ? null
        : subjects === undefined
          ? undefined
          : (get(ref) ?? null),
    error,
    refresh,
  };
}
