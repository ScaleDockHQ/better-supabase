/** How many steps Undo can go back. */
export const HISTORY_LIMIT = 50;

export interface History<T> {
  readonly past: readonly T[];
  readonly present: T;
  readonly future: readonly T[];
  /**
   * The value before the drag in progress, which `commitDrag` records as one
   * step.
   */
  readonly dragStart: T | null;
}

export type HistoryAction<T> =
  | { readonly type: "apply"; readonly value: T }
  | { readonly type: "drag"; readonly value: T }
  | { readonly type: "commitDrag" }
  | { readonly type: "amend"; readonly value: T }
  | { readonly type: "undo" }
  | { readonly type: "redo" }
  | { readonly type: "reset"; readonly value: T };

export function initialHistory<T>(value: T): History<T> {
  return { past: [], present: value, future: [], dragStart: null };
}

function record<T>(history: History<T>, previous: T, next: T): History<T> {
  return {
    past: [...history.past, previous].slice(-HISTORY_LIMIT),
    present: next,
    future: [],
    dragStart: null,
  };
}

/**
 * An undo history. `drag` updates the value without a step while the pointer
 * moves; `commitDrag` records the whole drag as one step. `amend` replaces the
 * value in the current step, so a follow-up such as placing a dropped block
 * stays part of the step that added it. `reset` replaces the value and clears
 * the history, as loading a link does.
 */
export function undoHistory<T>(
  current: History<T>,
  action: HistoryAction<T>,
): History<T> {
  switch (action.type) {
    case "apply": {
      return action.value === current.present
        ? current
        : record(current, current.dragStart ?? current.present, action.value);
    }

    case "drag": {
      return {
        ...current,
        present: action.value,
        dragStart: current.dragStart ?? current.present,
      };
    }

    case "commitDrag": {
      return current.dragStart === null
        ? current
        : record(current, current.dragStart, current.present);
    }

    case "amend": {
      return { ...current, present: action.value };
    }

    case "undo": {
      const previous = current.past.at(-1);

      return previous === undefined
        ? current
        : {
            past: current.past.slice(0, -1),
            present: previous,
            future: [current.present, ...current.future],
            dragStart: null,
          };
    }

    case "redo": {
      const [next, ...future] = current.future;

      return next === undefined
        ? current
        : {
            past: [...current.past, current.present].slice(-HISTORY_LIMIT),
            present: next,
            future,
            dragStart: null,
          };
    }

    case "reset": {
      return initialHistory(action.value);
    }

    default: {
      const unreachable: never = action;

      return unreachable;
    }
  }
}
