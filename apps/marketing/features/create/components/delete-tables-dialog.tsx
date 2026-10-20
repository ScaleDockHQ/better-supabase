"use client";

import type { ReactElement } from "react";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

/** The app tables a delete would remove, and the tables outside it that reference them. */
export interface PendingDelete {
  readonly names: readonly string[];
  readonly referencedBy: readonly string[];
}

function describe({ names, referencedBy }: PendingDelete): string {
  if (referencedBy.length === 0) {
    return "Undo brings it back.";
  }

  const one = names.length === 1;

  return `${referencedBy.join(", ")} ${
    referencedBy.length === 1 ? "references" : "reference"
  } ${one ? "this table" : "these tables"}. Deleting ${one ? "it" : "them"} also removes those columns.`;
}

/** Confirms deleting app tables that other tables reference. */
export function DeleteTablesDialog({
  pending,
  onCancel,
  onConfirm,
}: {
  readonly pending: PendingDelete | null;
  readonly onCancel: () => void;
  readonly onConfirm: (names: readonly string[]) => void;
}): ReactElement {
  return (
    <AlertDialog
      open={pending !== null}
      onOpenChange={(next) => {
        if (!next) {
          onCancel();
        }
      }}
    >
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            Delete {pending?.names.join(", ")}?
          </AlertDialogTitle>
          <AlertDialogDescription>
            {pending === null ? null : describe(pending)}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            onClick={() => {
              if (pending !== null) {
                onConfirm(pending.names);
              }

              onCancel();
            }}
          >
            Delete
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
