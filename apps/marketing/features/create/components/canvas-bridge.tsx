"use client";

import type { ReactElement, ReactNode } from "react";

import { createContext, use, useMemo, useState } from "react";

import type { PrimitiveKind } from "@/lib/primitives";

/** What the side menu can ask of the canvas while it is on screen. */
export interface CanvasCommands {
  /** Adds a primitive at the centre of the view and opens it. */
  readonly addPrimitive: (kind: PrimitiveKind) => void;
}

/** A block the canvas asked the side menu to show; `nonce` repeats a request. */
export interface BlockReveal {
  readonly name: string;
  readonly nonce: number;
}

export interface CanvasBridgeValue {
  readonly state: {
    readonly commands: CanvasCommands | null;
    readonly reveal: BlockReveal | null;
  };
  readonly actions: {
    /** The canvas registers its commands on mount and `null` on unmount. */
    readonly register: (commands: CanvasCommands | null) => void;
    /** Opens the block's row in the side menu. */
    readonly showBlock: (name: string) => void;
    /** The side menu calls this once it has shown the block. */
    readonly revealed: () => void;
  };
}

const CanvasBridgeContext = createContext<CanvasBridgeValue | null>(null);

/**
 * The link between the side menu and the canvas, which sit in different
 * branches: the menu adds primitives through the canvas, and the canvas
 * points at a block in the menu. `onShowBlock` lets the page open the menu
 * when it is a sheet.
 */
export function useCanvasBridgeState(
  onShowBlock: () => void,
): CanvasBridgeValue {
  const [commands, setCommands] = useState<CanvasCommands | null>(null);
  const [reveal, setReveal] = useState<BlockReveal | null>(null);

  const actions = useMemo(
    (): CanvasBridgeValue["actions"] => ({
      register: setCommands,
      showBlock: (name) => {
        setReveal((current) => ({ name, nonce: (current?.nonce ?? 0) + 1 }));
        onShowBlock();
      },
      revealed: () => {
        setReveal(null);
      },
    }),
    [onShowBlock],
  );

  return useMemo(
    () => ({ state: { commands, reveal }, actions }),
    [actions, commands, reveal],
  );
}

export function CanvasBridgeProvider({
  value,
  children,
}: {
  value: CanvasBridgeValue;
  children: ReactNode;
}): ReactElement {
  return <CanvasBridgeContext value={value}>{children}</CanvasBridgeContext>;
}

export function useCanvasBridge(): CanvasBridgeValue {
  const value = use(CanvasBridgeContext);

  if (value === null) {
    throw new Error("useCanvasBridge needs a CanvasBridgeProvider.");
  }

  return value;
}
