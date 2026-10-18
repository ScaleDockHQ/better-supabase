"use client";

import type { Preset } from "better-supabase/preset";
import type { ReactElement, ReactNode } from "react";

import { createContext, use, useMemo, useReducer } from "react";

import type { Design } from "@/lib/design";

import {
  createReducer,
  initialCreateState,
  shownPreset,
} from "@/lib/create-state";

export interface DesignContextValue {
  readonly state: {
    readonly preset: Preset;
    readonly design: Design;
    readonly canUndo: boolean;
    readonly canRedo: boolean;
  };
  readonly actions: {
    /** Records one step. */
    readonly apply: (design: Design) => void;
    /** Moves tables without a step, until `commitDrag`. */
    readonly drag: (design: Design) => void;
    readonly commitDrag: () => void;
    /** Changes the design inside the last step, such as placing a dropped block. */
    readonly place: (design: Design) => void;
    /** A design change and a block list as one step. */
    readonly step: (design: Design, blocks: Preset["blocks"]) => void;
    /** A changed block list is one step; other preset fields change in place. */
    readonly setPreset: (update: (current: Preset) => Preset) => void;
    readonly undo: () => void;
    readonly redo: () => void;
    /** Replaces the design and clears the history. */
    readonly reset: (design: Design) => void;
    /** Replaces the preset and the design and clears the history. */
    readonly restore: (preset: Preset, design: Design) => void;
  };
}

const DesignContext = createContext<DesignContextValue | null>(null);

/** The preset and the design with their history, for the options, the canvas and the URL. */
export function useDesignState(
  preset: () => Preset,
  design: Design,
): DesignContextValue {
  const [current, dispatch] = useReducer(createReducer, undefined, () =>
    initialCreateState(preset(), design),
  );

  const actions = useMemo(
    (): DesignContextValue["actions"] => ({
      apply: (next) => {
        dispatch({ type: "design", design: next });
      },
      drag: (next) => {
        dispatch({ type: "drag", design: next });
      },
      commitDrag: () => {
        dispatch({ type: "commitDrag" });
      },
      place: (next) => {
        dispatch({ type: "place", design: next });
      },
      step: (next, blocks) => {
        dispatch({ type: "step", design: next, blocks });
      },
      setPreset: (update) => {
        dispatch({ type: "preset", update });
      },
      undo: () => {
        dispatch({ type: "undo" });
      },
      redo: () => {
        dispatch({ type: "redo" });
      },
      reset: (next) => {
        dispatch({ type: "load", design: next });
      },
      restore: (nextPreset, nextDesign) => {
        dispatch({ type: "restore", preset: nextPreset, design: nextDesign });
      },
    }),
    [],
  );

  const { settings } = current;
  const { blocks } = current.history.present;

  const shown = useMemo(
    () => shownPreset(settings, blocks),
    [settings, blocks],
  );

  return {
    state: {
      preset: shown,
      design: current.history.present.design,
      canUndo: current.history.past.length > 0,
      canRedo: current.history.future.length > 0,
    },
    actions,
  };
}

export function DesignProvider({
  value,
  children,
}: {
  value: DesignContextValue;
  children: ReactNode;
}): ReactElement {
  return <DesignContext value={value}>{children}</DesignContext>;
}

export function useDesign(): DesignContextValue {
  const value = use(DesignContext);

  if (value === null) {
    throw new Error("useDesign needs a DesignProvider.");
  }

  return value;
}
