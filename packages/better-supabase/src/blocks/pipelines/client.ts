import type { Controller } from "../controller.ts";

import { defineController } from "../controller.ts";

/** What the board needs of a card: its id. */
export interface BoardCard {
  readonly id: string;
}

/** One lane (a pipeline stage) of a board, with its cards in order. */
export interface BoardLane<T extends BoardCard> {
  readonly id: string;
  readonly cards: readonly T[];
}

export interface BoardMove {
  readonly cardId: string;
  readonly from: string;
  readonly to: string;
  /** The position in the target lane the card landed at. */
  readonly index: number;
}

export interface BoardOptions<T extends BoardCard> {
  /** The lanes to start with, e.g. the board's read set. */
  readonly lanes: readonly BoardLane<T>[];
  /**
   * Saves a move, e.g. a server action that transitions the record. A throw or
   * a rejected promise puts the card back where it was.
   */
  readonly move: (move: BoardMove) => Promise<unknown>;
}

export interface BoardSnapshot<T extends BoardCard> {
  readonly lanes: readonly BoardLane<T>[];
  /** How many moves are waiting for the server. */
  readonly saving: number;
  /** What the last failed move threw; cleared by the next move. */
  readonly error: unknown;
}

export interface BoardActions<T extends BoardCard> {
  /**
   * Moves a card now and saves it. Resolves whether the server accepted it; a
   * move onto its own place, or of an unknown card or lane, resolves `false`
   * without calling the server.
   */
  readonly move: (input: {
    readonly cardId: string;
    readonly to: string;
    readonly index?: number;
  }) => Promise<boolean>;
  /** Replaces the lanes with fresh server data, e.g. after a revalidation. */
  readonly setLanes: (lanes: readonly BoardLane<T>[]) => void;
}

export type BoardController<T extends BoardCard> = Controller<
  BoardSnapshot<T>,
  BoardActions<T>
>;

function place<T extends BoardCard>(
  lanes: readonly BoardLane<T>[],
  cardId: string,
  to: string,
  index: number | undefined,
): { lanes: readonly BoardLane<T>[]; move: BoardMove } | undefined {
  const source = lanes.find((lane) => lane.cards.some((c) => c.id === cardId));
  const target = lanes.find((lane) => lane.id === to);
  const card = source?.cards.find((c) => c.id === cardId);

  if (!source || !target || !card) {
    return undefined;
  }

  const without = source.cards.filter((c) => c.id !== cardId);
  const base = source.id === target.id ? without : target.cards;
  const at = Math.min(Math.max(index ?? base.length, 0), base.length);

  if (
    source.id === target.id &&
    source.cards.findIndex((c) => c.id === cardId) === at
  ) {
    return undefined;
  }

  const inserted = [...base.slice(0, at), card, ...base.slice(at)];

  return {
    move: { cardId, from: source.id, to, index: at },
    lanes: lanes.map((lane) => {
      if (lane.id === target.id) {
        return { ...lane, cards: inserted };
      }

      return lane.id === source.id ? { ...lane, cards: without } : lane;
    }),
  };
}

/**
 * A board's lanes on the client: a card moves at once, the server saves it, and
 * a failed save puts every lane back as it was before that move.
 */
export function createBoardController<T extends BoardCard>(
  options: BoardOptions<T>,
): BoardController<T> {
  return defineController<BoardSnapshot<T>, BoardActions<T>>(
    { lanes: options.lanes, saving: 0, error: undefined },
    (state) => ({
      actions: {
        setLanes: (lanes) => {
          state.set({ lanes });
        },
        move: async ({ cardId, to, index }) => {
          const before = state.get().lanes;
          const placed = place(before, cardId, to, index);

          if (!placed) {
            return false;
          }

          state.set((current) => ({
            lanes: placed.lanes,
            saving: current.saving + 1,
            error: undefined,
          }));

          try {
            await options.move(placed.move);
            state.set((current) => ({ saving: current.saving - 1 }));

            return true;
          } catch (error) {
            state.set((current) => ({
              // Undo only while the board is still the one this move made; after
              // another move or a reload, `error` tells the app to refetch.
              lanes: current.lanes === placed.lanes ? before : current.lanes,
              saving: current.saving - 1,
              error,
            }));

            return false;
          }
        },
      },
    }),
  );
}
