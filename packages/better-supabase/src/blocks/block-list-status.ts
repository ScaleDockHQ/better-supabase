import type { DbError } from "../core/errors.ts";
import type { BlockQueryState, BlockRefetchOn } from "./block-controller.ts";

/**
 * What a list shows for a block read: the one union the record list kit reads
 * instead of the raw `Result` and the four query statuses.
 */
export type BlockListStatus<Row> =
  | { readonly kind: "loading" }
  | { readonly kind: "empty" }
  | { readonly kind: "error"; readonly error: DbError }
  | { readonly kind: "ready"; readonly rows: readonly Row[] };

/**
 * The list status of a block read that returns rows. Rows already loaded stay
 * `ready` while the read runs again; a failed read is `error` even when older
 * rows exist.
 */
export function blockListStatus<Row>(
  state: BlockQueryState<readonly Row[]>,
): BlockListStatus<Row> {
  switch (state.status) {
    case "error": {
      return state.error === undefined
        ? { kind: "loading" }
        : { kind: "error", error: state.error };
    }

    case "idle":
    case "loading":
    case "success": {
      if (state.data === undefined) {
        return { kind: "loading" };
      }

      return state.data.length === 0
        ? { kind: "empty" }
        : { kind: "ready", rows: state.data };
    }

    default: {
      const never: never = state.status;

      return never;
    }
  }
}

/** The part of a block manifest that `blockRealtimeRefetch` reads. */
export interface BlockRealtimeManifest {
  readonly events: { readonly types: readonly string[] };
  readonly entities: Readonly<
    Record<string, { readonly realtime?: boolean | undefined }>
  >;
}

/**
 * The `refetchOn` of a list over one entity: the entity's block events when its
 * manifest declares `realtime: true`, otherwise `undefined` so the list does
 * not subscribe. The events are the types that start with `<entity>.`; an
 * entity whose events use another prefix listens to every event of the block.
 */
export function blockRealtimeRefetch(
  block: BlockRealtimeManifest,
  entity: string,
  source: BlockRefetchOn["source"],
): BlockRefetchOn | undefined {
  if (block.entities[entity]?.realtime !== true) {
    return undefined;
  }

  const own = block.events.types.filter((type) =>
    type.startsWith(`${entity}.`),
  );

  return { source, types: own.length > 0 ? own : block.events.types };
}
