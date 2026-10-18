import type { Preset } from "better-supabase/preset";

import type { Design } from "./design";

import { type History, initialHistory, undoHistory } from "./design-history";

/**
 * One undo step: the design and the blocks. The other preset fields stay out
 * of the history, so Undo never reverts a framework or a naming convention.
 */
export interface CreateStep {
  readonly design: Design;
  readonly blocks: Preset["blocks"];
}

export interface CreateState {
  readonly settings: Preset;
  readonly history: History<CreateStep>;
}

export type CreateAction =
  /** Records a design change as one step. */
  | { readonly type: "design"; readonly design: Design }
  /** Records a design change and a block list as one step. */
  | {
      readonly type: "step";
      readonly design: Design;
      readonly blocks: Preset["blocks"];
    }
  /** Moves tables without a step, until `commitDrag`. */
  | { readonly type: "drag"; readonly design: Design }
  | { readonly type: "commitDrag" }
  /** Changes the design inside the current step. */
  | { readonly type: "place"; readonly design: Design }
  /** A changed block list is one step; other fields change in place. */
  | { readonly type: "preset"; readonly update: (current: Preset) => Preset }
  | { readonly type: "undo" }
  | { readonly type: "redo" }
  /** Replaces the design and clears the history, as loading a link does. */
  | { readonly type: "load"; readonly design: Design }
  /** Replaces both and clears the history, as restoring a draft does. */
  | {
      readonly type: "restore";
      readonly preset: Preset;
      readonly design: Design;
    };

export function initialCreateState(
  preset: Preset,
  design: Design,
): CreateState {
  return {
    settings: preset,
    history: initialHistory({ design, blocks: preset.blocks }),
  };
}

/** The preset the page shows: the settings with the blocks of the current step. */
export function shownPreset(
  settings: Preset,
  blocks: Preset["blocks"],
): Preset {
  return settings.blocks === blocks ? settings : { ...settings, blocks };
}

export function presetOfState(state: CreateState): Preset {
  return shownPreset(state.settings, state.history.present.blocks);
}

function sameBlocks(a: Preset["blocks"], b: Preset["blocks"]): boolean {
  return a.length === b.length && a.every((name, index) => b[index] === name);
}

function withDesign(state: CreateState, design: Design): CreateStep {
  return { ...state.history.present, design };
}

export function createReducer(
  state: CreateState,
  action: CreateAction,
): CreateState {
  switch (action.type) {
    case "design": {
      return action.design === state.history.present.design
        ? state
        : {
            ...state,
            history: undoHistory(state.history, {
              type: "apply",
              value: withDesign(state, action.design),
            }),
          };
    }

    case "step": {
      const { present } = state.history;

      return action.design === present.design &&
        sameBlocks(action.blocks, present.blocks)
        ? state
        : {
            settings: { ...state.settings, blocks: action.blocks },
            history: undoHistory(state.history, {
              type: "apply",
              value: { design: action.design, blocks: action.blocks },
            }),
          };
    }

    case "drag": {
      return {
        ...state,
        history: undoHistory(state.history, {
          type: "drag",
          value: withDesign(state, action.design),
        }),
      };
    }

    case "commitDrag": {
      return {
        ...state,
        history: undoHistory(state.history, { type: "commitDrag" }),
      };
    }

    case "place": {
      return {
        ...state,
        history: undoHistory(state.history, {
          type: "amend",
          value: withDesign(state, action.design),
        }),
      };
    }

    case "preset": {
      const next = action.update(presetOfState(state));
      const { present } = state.history;

      return {
        settings: next,
        history: sameBlocks(next.blocks, present.blocks)
          ? state.history
          : undoHistory(state.history, {
              type: "apply",
              value: { ...present, blocks: next.blocks },
            }),
      };
    }

    case "undo":
    case "redo": {
      return { ...state, history: undoHistory(state.history, action) };
    }

    case "load": {
      return {
        ...state,
        history: initialHistory(withDesign(state, action.design)),
      };
    }

    case "restore": {
      return initialCreateState(action.preset, action.design);
    }

    default: {
      const unreachable: never = action;

      return unreachable;
    }
  }
}
