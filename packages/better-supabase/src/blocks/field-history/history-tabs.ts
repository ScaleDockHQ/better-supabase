import type { BlockEntities } from "../entity-surface.ts";

/** What `historyTabs` reads of a block: its name and declared entities. */
export interface HistoryTabBlock {
  readonly name: string;
  readonly entities?: BlockEntities | undefined;
}

/** One entity that keeps column history, so a page can show a history tab. */
export interface HistoryTab {
  readonly block: string;
  readonly entity: string;
  /** The columns whose changes are kept; `undefined` for every column. */
  readonly fields: readonly string[] | undefined;
}

/**
 * Lists the entities whose manifest declares `history` (ADR 0902). A page shows
 * a history tab for each, reading `fieldHistory.of({ subject })` with the
 * entity's record type, instead of probing the database for a binding.
 */
export function historyTabs(
  blocks: readonly HistoryTabBlock[],
): readonly HistoryTab[] {
  return blocks.flatMap((block) =>
    Object.entries(block.entities ?? {}).flatMap(([entity, surface]) => {
      const history = surface.history;

      if (history === undefined || history === false) {
        return [];
      }

      return [
        {
          block: block.name,
          entity,
          fields: history === true ? undefined : history,
        },
      ];
    }),
  );
}
