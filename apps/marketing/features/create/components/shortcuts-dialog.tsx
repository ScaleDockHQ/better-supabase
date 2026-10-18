"use client";

import type { ReactElement } from "react";

import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Kbd, KbdGroup } from "@/components/ui/kbd";

import { useIsApplePlatform } from "./canvas-toolbar";

/** The canvas shortcuts, opened with `?` or the keyboard button. */
export function ShortcutsDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}): ReactElement {
  const apple = useIsApplePlatform();
  const mod = apple ? "⌘" : "Ctrl";
  const shift = apple ? "⇧" : "Shift";

  const shortcuts: readonly {
    readonly keys: readonly string[];
    readonly label: string;
  }[] = [
    { keys: ["N"], label: "Add a table" },
    { keys: [mod, "Z"], label: "Undo" },
    { keys: [shift, mod, "Z"], label: "Redo" },
    { keys: ["Enter"], label: "Open the selected table" },
    { keys: ["Delete"], label: "Delete the selected app table" },
    { keys: ["F"], label: "Focus on the selected table and its neighbours" },
    { keys: ["Esc"], label: "Clear the selection and the focus" },
    { keys: ["+"], label: "Zoom in" },
    { keys: ["-"], label: "Zoom out" },
    { keys: [shift, "1"], label: "Zoom to fit" },
    { keys: ["?"], label: "Show these shortcuts" },
  ];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Keyboard shortcuts</DialogTitle>
          <DialogDescription>
            They work while the canvas has focus and no field is being edited.
          </DialogDescription>
        </DialogHeader>
        <dl className="flex flex-col gap-2">
          {shortcuts.map((shortcut) => (
            <div
              key={shortcut.label}
              className="flex items-center justify-between gap-4 text-sm"
            >
              <dt className="text-muted-foreground">{shortcut.label}</dt>
              <dd>
                <KbdGroup>
                  {shortcut.keys.map((key) => (
                    <Kbd key={key}>{key}</Kbd>
                  ))}
                </KbdGroup>
              </dd>
            </div>
          ))}
        </dl>
      </DialogContent>
    </Dialog>
  );
}
