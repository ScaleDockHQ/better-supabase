import type { SectionResult, TimelineItem } from "../blocks/sections.ts";
import type { RecordRef } from "../schema/types.ts";
import type {
  LoadSectionsOptions,
  SectionBlocks,
  SectionName,
  SectionSource,
} from "./sections.ts";

import { findSection, loadSections } from "./sections.ts";

/** One entry of a record's timeline, with the section it came from. */
export interface TimelineEntry extends TimelineItem {
  readonly section: string;
}

/** What `loadTimeline` returns. */
export interface Timeline {
  /** Every section's entries, newest first. */
  readonly entries: readonly TimelineEntry[];
  /**
   * The sections that added nothing because they failed or the caller can't
   * read them, by name.
   */
  readonly skipped: Readonly<
    Record<string, Exclude<SectionResult<unknown>, { readonly kind: "ok" }>>
  >;
}

export interface LoadTimelineOptions<
  B extends SectionBlocks,
  N extends string,
> extends LoadSectionsOptions<B, N> {
  /** Default: every section with a `timeline`. */
  readonly sections?: readonly N[];
  /** The most entries to return, newest first. Default: all of them. */
  readonly limit?: number;
}

/** The section names of `blocks` whose sections map rows to timeline entries. */
export function timelineSections<B extends SectionBlocks>(
  blocks: B,
): readonly SectionName<B>[] {
  const names = new Set<string>();

  for (const block of Object.values(blocks)) {
    for (const [name, section] of Object.entries(block.sections ?? {})) {
      if (section.timeline !== undefined) {
        names.add(name);
      }
    }
  }

  // SAFETY: each name is a key of a block's `sections`.
  return [...names] as SectionName<B>[];
}

function newestFirst(a: TimelineEntry, b: TimelineEntry): number {
  const order = b.at.epochNanoseconds - a.at.epochNanoseconds;

  return order === 0n
    ? a.section.localeCompare(b.section) || a.id.localeCompare(b.id)
    : order > 0n
      ? 1
      : -1;
}

/**
 * A record's history across its sections, newest first: comments, files and
 * versions, each section loaded once through `loadSections` and mapped by its
 * `timeline`. A section that fails or that `can` hides adds nothing and is
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
  B extends SectionBlocks,
  const N extends SectionName<B>,
>(
  source: SectionSource<B>,
  subject: RecordRef,
  options: LoadTimelineOptions<B, N> = {},
): Promise<Timeline> {
  // SAFETY: without `sections` every timeline section loads, which is `N` at
  // its default.
  const names = options.sections ?? (timelineSections(source.blocks) as N[]);
  const loaded = await loadSections(source, subject, names, options);
  const entries: TimelineEntry[] = [];
  const skipped: Record<string, Timeline["skipped"][string]> = {};

  for (const name of names) {
    // SAFETY: a read of one key of the results typed by section name.
    const result = (loaded as Readonly<Record<string, SectionResult<unknown>>>)[
      name
    ];

    // SAFETY: the section maps the rows its own `load` returned.
    const timeline = findSection(source.blocks, name)?.section.timeline as
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
      entries.push({ ...item, section: name });
    }
  }

  entries.sort(newestFirst);

  return {
    entries:
      options.limit === undefined ? entries : entries.slice(0, options.limit),
    skipped,
  };
}
