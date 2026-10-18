"use client";

import type { CSSProperties, ReactElement } from "react";

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { PRIMITIVES, type PrimitiveKind } from "@/lib/primitives";

import { PRIMITIVE_ICONS } from "./primitive-picker";

/** A connection dropped on empty canvas: where, and from which table. */
export interface ConnectDrop {
  readonly from: string;
  readonly fromName: string;
  /** Viewport coordinates of the drop. */
  readonly x: number;
  readonly y: number;
}

/**
 * Offers a new table from the primitives at the point where a connection
 * was dropped on empty canvas. The new table references the one the drag
 * started from.
 */
export function ConnectDropMenu({
  drop,
  onPick,
  onClose,
}: {
  readonly drop: ConnectDrop | null;
  readonly onPick: (kind: PrimitiveKind, drop: ConnectDrop) => void;
  readonly onClose: () => void;
}): ReactElement | null {
  if (drop === null) {
    return null;
  }

  const at: CSSProperties & Record<"--drop-x" | "--drop-y", string> = {
    "--drop-x": `${String(drop.x)}px`,
    "--drop-y": `${String(drop.y)}px`,
  };

  return (
    <DropdownMenu
      open
      onOpenChange={(open) => {
        if (!open) {
          onClose();
        }
      }}
    >
      <DropdownMenuTrigger
        aria-hidden="true"
        tabIndex={-1}
        className="pointer-events-none fixed top-(--drop-y) left-(--drop-x) size-px opacity-0"
        style={at}
      />
      <DropdownMenuContent className="w-56">
        <DropdownMenuGroup>
          <DropdownMenuLabel>
            New table referencing {drop.fromName}
          </DropdownMenuLabel>
          {PRIMITIVES.map((primitive) => {
            const Icon = PRIMITIVE_ICONS[primitive.kind];

            return (
              <DropdownMenuItem
                key={primitive.kind}
                onClick={() => {
                  onPick(primitive.kind, drop);
                }}
              >
                <Icon aria-hidden="true" />
                {primitive.title}
              </DropdownMenuItem>
            );
          })}
        </DropdownMenuGroup>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
