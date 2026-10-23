import type {
  RecordBindingResult,
  TimelineItem,
} from "../blocks/record-bindings.ts";
import type { RecordRef } from "../schema/types.ts";
import type {
  LoadBindingsOptions,
  BindingBlocks,
  BindingName,
  BindingSource,
} from "./bindings.ts";

import { findBinding, loadBindings } from "./bindings.ts";

/** One entry of a record's timeline, with the binding it came from. */
export interface TimelineEntry extends TimelineItem {
  readonly binding: string;
}

/** What `loadTimeline` returns. */
export interface Timeline {
  /** Every binding's entries, newest first. */
  readonly entries: readonly TimelineEntry[];
  /**
   * The bindings that added nothing because they failed or the caller can't
   * read them, by name.
   */
  readonly skipped: Readonly<
    Record<
      string,
      Exclude<RecordBindingResult<unknown>, { readonly kind: "ok" }>
    >
  >;
}

export interface LoadTimelineOptions<
  B extends BindingBlocks,
  N extends string,
> extends LoadBindingsOptions<B, N> {
  /** Default: every binding with a `timeline`. */
  readonly bindings?: readonly N[];
  /** The most entries to return, newest first. Default: all of them. */
  readonly limit?: number;
}

/** The binding names of `blocks` whose bindings map rows to timeline entries. */
export function timelineBindings<B extends BindingBlocks>(
  blocks: B,
): readonly BindingName<B>[] {
  const names = Object.entries(blocks).flatMap(([key, block]) =>
    block.record?.timeline === undefined ? [] : [key],
  );

  // SAFETY: each name keys a block with a record binding.
  return names as BindingName<B>[];
}

function newestFirst(a: TimelineEntry, b: TimelineEntry): number {
  const order = b.at.epochNanoseconds - a.at.epochNanoseconds;

  return order === 0n
    ? a.binding.localeCompare(b.binding) || a.id.localeCompare(b.id)
    : order > 0n
      ? 1
      : -1;
}

/**
 * A record's history across its bindings, newest first: comments, files and
 * versions, each binding loaded once through `loadBindings` and mapped by its
 * `timeline`. A binding that fails or that `can` hides adds nothing and is
 * listed in `skipped`; it never throws.
 *
 * ```ts
 * const { entries } = await loadTimeline(
 *   { blocks: blockSet.blocks, clients: blocks },
 *   { type: "customer", id },
 *   { limit: 50 },
 * );
 * ```
 */
export async function loadTimeline<
  B extends BindingBlocks,
  const N extends BindingName<B>,
>(
  source: BindingSource<B>,
  subject: RecordRef,
  options: LoadTimelineOptions<B, N> = {},
): Promise<Timeline> {
  // SAFETY: without `bindings` every timeline binding loads, which is `N` at
  // its default.
  const names = options.bindings ?? (timelineBindings(source.blocks) as N[]);
  const loaded = await loadBindings(source, subject, names, options);
  const entries: TimelineEntry[] = [];
  const skipped: Record<string, Timeline["skipped"][string]> = {};

  for (const name of names) {
    // SAFETY: a read of one key of the results typed by binding name.
    const result = (
      loaded as Readonly<Record<string, RecordBindingResult<unknown>>>
    )[name];

    // SAFETY: the binding maps the rows its own `load` returned.
    const timeline = findBinding(source.blocks, name)?.binding.timeline as
      | ((data: unknown) => readonly TimelineItem[])
      | undefined;

    if (result === undefined) {
      continue;
    }

    if (result.kind !== "ok") {
      skipped[name] = result;
      continue;
    }

    for (const item of timeline?.(result.data) ?? []) {
      entries.push({ ...item, binding: name });
    }
  }

  entries.sort(newestFirst);

  return {
    entries:
      options.limit === undefined ? entries : entries.slice(0, options.limit),
    skipped,
  };
}
