"use client";

import type { ReactElement, ReactNode } from "react";

import { createContext, use, useMemo, useReducer } from "react";

import type { Design } from "@/lib/design";

import {
  designHistory,
  type DesignHistory,
  initialHistory,
} from "@/lib/design-history";

export interface DesignContextValue {
  readonly state: {
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
    readonly undo: () => void;
    readonly redo: () => void;
    /** Replaces the design and clears the history. */
    readonly reset: (design: Design) => void;
  };
}

const DesignContext = createContext<DesignContextValue | null>(null);

/** The design history for the canvas, the inspector and the URL. */
export function useDesignState(initial?: Design): DesignContextValue {
  const [history, dispatch] = useReducer(
    designHistory,
    initial,
    (design): DesignHistory => initialHistory(design),
  );

  const actions = useMemo(
    (): DesignContextValue["actions"] => ({
      apply: (design) => {
        dispatch({ type: "apply", design });
      },
      drag: (design) => {
        dispatch({ type: "drag", design });
      },
      commitDrag: () => {
        dispatch({ type: "commitDrag" });
      },
      undo: () => {
        dispatch({ type: "undo" });
      },
      redo: () => {
        dispatch({ type: "redo" });
      },
      reset: (design) => {
        dispatch({ type: "reset", design });
      },
    }),
    [],
  );

  return {
    state: {
      design: history.present,
      canUndo: history.past.length > 0,
      canRedo: history.future.length > 0,
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
