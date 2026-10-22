import type { DbError } from "../../core/errors.ts";
import type { Result } from "../../core/result.ts";
import type { SubjectRef } from "../../schema/types.ts";
import type { AuthPort, Controller } from "../controller.ts";
import type { ResolvedSubject, Subjects } from "./subjects.ts";

import { subjectKey } from "../../core/block-subjects.ts";
import { AsyncResult, ok } from "../../core/result.ts";
import { defineController, whileSignedIn } from "../controller.ts";

type Resolved = Readonly<Record<string, ResolvedSubject>>;

interface Batch {
  readonly refs: Map<string, SubjectRef>;
  readonly waiters: ((result: Result<Resolved>) => void)[];
}

/**
 * Joins the `resolve(refs)` calls made in the same tick into one, so a list
 * where each row shows a subject link costs one round trip. Each caller gets
 * back only the subjects it asked for.
 */
export function batchSubjects(source: Subjects): Subjects {
  let pending: Batch | undefined;

  const flush = (batch: Batch): void => {
    pending = undefined;

    void source.resolve([...batch.refs.values()]).then((result) => {
      for (const waiter of batch.waiters) {
        waiter(result);
      }
    });
  };

  return {
    resolve: (refs) =>
      AsyncResult.from(
        () =>
          new Promise((resolve) => {
            if (pending === undefined) {
              const created: Batch = { refs: new Map(), waiters: [] };
              pending = created;
              queueMicrotask(() => {
                flush(created);
              });
            }

            const keys = refs.map((ref) => subjectKey(ref));

            for (const [index, ref] of refs.entries()) {
              pending.refs.set(keys[index]!, ref);
            }

            pending.waiters.push((result) => {
              if (!result.ok) {
                resolve(result);

                return;
              }

              const mine: Record<string, ResolvedSubject> = {};

              for (const key of keys) {
                const found = result.data[key];

                if (found !== undefined) {
                  mine[key] = found;
                }
              }

              resolve(ok(mine));
            });
          }),
      ),
  };
}

export interface SubjectsControllerOptions {
  /** `createSubjects()`, ideally through `batchSubjects`. */
  readonly client: Pick<Subjects, "resolve">;
  readonly auth: AuthPort;
  /** The subjects to resolve; nothing loads while empty. */
  readonly refs: readonly SubjectRef[];
}

export interface SubjectsSnapshot {
  /**
   * The resolved subjects keyed by `subjectKey` (`type:id`); `undefined` until
   * the first load. A subject the caller can't read is missing.
   */
  readonly subjects: Readonly<Record<string, ResolvedSubject>> | undefined;
  readonly error: DbError | undefined;
}

export interface SubjectsActions {
  /** Resolves the subjects again, such as after a rename. */
  readonly refresh: () => Promise<void>;
}

export type SubjectsController = Controller<SubjectsSnapshot, SubjectsActions>;

/**
 * Titles and paths of `refs`, loaded for the signed-in user and again when
 * another user signs in.
 */
export function createSubjectsController(
  options: SubjectsControllerOptions,
): SubjectsController {
  const { client, refs } = options;

  return defineController<SubjectsSnapshot, SubjectsActions>(
    { subjects: undefined, error: undefined },
    (state) => {
      const refresh = async (): Promise<void> => {
        if (refs.length === 0) {
          state.set({ subjects: {}, error: undefined });

          return;
        }

        const run = state.run();
        const result = await client.resolve(refs);

        if (run !== state.run()) {
          return;
        }

        state.set(
          result.ok
            ? { subjects: result.data, error: undefined }
            : { error: result.error },
        );
      };

      return {
        actions: { refresh },
        start: () =>
          whileSignedIn(options.auth, () => {
            void refresh();

            return;
          }),
      };
    },
  );
}
