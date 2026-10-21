import type {
  MyWorkItem,
  MyWorkKind,
  MyWorkOptions,
  Subjects,
} from "../blocks/subjects/subjects.ts";
import type { AsyncResult } from "../core/result.ts";

import { MY_WORK_KINDS } from "../blocks/subjects/subjects.ts";

/** What `loadMyWork` returns: the items, grouped by kind, and their counts. */
export interface MyWork {
  /** Every item, newest first. */
  readonly items: readonly MyWorkItem[];
  /** The items of each kind, newest first; an empty list for a kind with none. */
  readonly groups: Readonly<Record<MyWorkKind, readonly MyWorkItem[]>>;
  /** How many items of each kind the page holds, for tab badges. */
  readonly counts: Readonly<Record<MyWorkKind, number>>;
}

export interface LoadMyWorkOptions extends MyWorkOptions {
  /** Only these kinds, such as `["assigned", "approval"]`. Default: all. */
  readonly kinds?: readonly MyWorkKind[];
}

/**
 * The caller's "My work" page: `my_work` across the installed blocks, grouped
 * by kind with a count each, in one round trip.
 *
 * ```ts
 * const work = await loadMyWork(blocks.subjects, {
 *   pageSize: 100,
 * }).orThrow();
 * work.groups.approval; // approvals the caller can decide
 * ```
 */
export function loadMyWork(
  subjects: Pick<Subjects, "myWork">,
  options: LoadMyWorkOptions = {},
): AsyncResult<MyWork> {
  const { kinds, ...rest } = options;
  const wanted = new Set(kinds ?? MY_WORK_KINDS);

  return subjects.myWork(rest).map((all) => {
    const items = all.filter((item) => wanted.has(item.kind));

    const of = (kind: MyWorkKind): readonly MyWorkItem[] =>
      items.filter((item) => item.kind === kind);

    const groups = {
      assigned: of("assigned"),
      approval: of("approval"),
      reminder: of("reminder"),
      mention: of("mention"),
      sla: of("sla"),
    } satisfies Record<MyWorkKind, readonly MyWorkItem[]>;

    const counts = {
      assigned: groups.assigned.length,
      approval: groups.approval.length,
      reminder: groups.reminder.length,
      mention: groups.mention.length,
      sla: groups.sla.length,
    } satisfies Record<MyWorkKind, number>;

    return { items, groups, counts };
  });
}
