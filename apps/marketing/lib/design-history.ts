import { type Design, EMPTY_DESIGN } from "./design";

/** How many steps Undo can go back. */
export const HISTORY_LIMIT = 50;

export interface DesignHistory {
  readonly past: readonly Design[];
  readonly present: Design;
  readonly future: readonly Design[];
  /** The design before the drag in progress, which `commitDrag` records as one step. */
  readonly dragStart: Design | null;
}

export type DesignAction =
  | { readonly type: "apply"; readonly design: Design }
  | { readonly type: "drag"; readonly design: Design }
  | { readonly type: "commitDrag" }
  | { readonly type: "undo" }
  | { readonly type: "redo" }
  | { readonly type: "reset"; readonly design: Design };

export function initialHistory(design: Design = EMPTY_DESIGN): DesignHistory {
  return { past: [], present: design, future: [], dragStart: null };
}

function record(
  history: DesignHistory,
  previous: Design,
  next: Design,
): DesignHistory {
  return {
    past: [...history.past, previous].slice(-HISTORY_LIMIT),
    present: next,
    future: [],
    dragStart: null,
  };
}

/**
 * The design history. `drag` updates the design without a step while the
 * pointer moves; `commitDrag` records the whole drag as one step. `reset`
 * replaces the design and clears the history, as loading a link does.
 */
export function designHistory(
  history: DesignHistory,
  action: DesignAction,
): DesignHistory {
  switch (action.type) {
    case "apply": {
      return action.design === history.present
        ? history
        : record(history, history.dragStart ?? history.present, action.design);
    }

    case "drag": {
      return {
        ...history,
        present: action.design,
        dragStart: history.dragStart ?? history.present,
      };
    }

    case "commitDrag": {
      return history.dragStart === null
        ? history
        : record(history, history.dragStart, history.present);
    }

    case "undo": {
      const previous = history.past.at(-1);

      return previous === undefined
        ? history
        : {
            past: history.past.slice(0, -1),
            present: previous,
            future: [history.present, ...history.future],
            dragStart: null,
          };
    }

    case "redo": {
      const [next, ...future] = history.future;

      return next === undefined
        ? history
        : {
            past: [...history.past, history.present].slice(-HISTORY_LIMIT),
            present: next,
            future,
            dragStart: null,
          };
    }

    case "reset": {
      return initialHistory(action.design);
    }

    default: {
      const unreachable: never = action;

      return unreachable;
    }
  }
}
