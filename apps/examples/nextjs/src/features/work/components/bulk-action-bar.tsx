"use client";

import type { WorkItemState } from "better-supabase/blocks/work-items";

import { useAction } from "better-supabase/react";
import { Trash2Icon, TriangleAlertIcon, XIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useErrorMessage } from "@/lib/use-error-message";

import type { WorkItemRow } from "../work-types";

import { useStateLabel } from "../use-work-labels";
import { runWorkBulkAction } from "../work-actions";
import { WORK_ITEM_STATES } from "../work-types";

interface BulkFailure {
  readonly id: string;
  readonly identifier: string;
  readonly message: string;
}

// #region recipe:bulk-action-bar
/**
 * The bar over the grid's selected rows. It changes their state or moves them
 * to the trash through the bulk block, which runs each row on its own; the rows
 * that failed stay selected and are listed with their reason.
 */
export function BulkActionBar({
  selected,
  onSettled,
}: {
  selected: readonly Pick<WorkItemRow, "id" | "identifier">[];
  onSettled: (failedIds: readonly string[]) => void;
}) {
  const t = useExtracted("work");
  const errorMessage = useErrorMessage();
  const stateLabel = useStateLabel();
  const [to, setTo] = useState<WorkItemState | null>(null);
  const [confirming, setConfirming] = useState(false);
  const [failures, setFailures] = useState<readonly BulkFailure[]>([]);
  const bulk = useAction(runWorkBulkAction);

  const identifiers = new Map(selected.map((row) => [row.id, row.identifier]));

  const run = async (
    input: { action: "state"; to: WorkItemState } | { action: "delete" },
  ): Promise<void> => {
    const ids = selected.map((row) => row.id);
    const result = await bulk.run({ ...input, ids });

    if (!result.ok) {
      toast.error(errorMessage(result.error));

      return;
    }

    const { succeeded, failed } = result.data;

    setFailures(
      failed.map((row) => ({
        id: row.id,
        identifier: identifiers.get(row.id) ?? row.id,
        message: row.message === "" ? t("No reason given.") : row.message,
      })),
    );

    if (failed.length === 0) {
      toast.success(
        t("{count, plural, one {# item updated} other {# items updated}}", {
          count: succeeded,
        }),
      );
    } else {
      toast.warning(
        t("{failed, number} of {total, number} items failed", {
          failed: failed.length,
          total: result.data.total,
        }),
      );
    }

    onSettled(failed.map((row) => row.id));
  };

  const stateItems = WORK_ITEM_STATES.map((state) => ({
    value: state,
    label: stateLabel(state),
  }));

  if (selected.length === 0 && failures.length === 0) {
    return null;
  }

  return (
    <div className="flex flex-col gap-3" data-recipe="bulk-action-bar">
      {selected.length === 0 ? null : (
        <div
          role="toolbar"
          aria-label={t("Selected items")}
          className="flex flex-wrap items-center gap-2 rounded-lg border bg-muted/50 p-2"
        >
          <span className="px-2 text-sm font-medium tabular-nums">
            {t("{count, plural, one {# selected} other {# selected}}", {
              count: selected.length,
            })}
          </span>
          <Select
            value={to}
            items={stateItems}
            disabled={bulk.pending}
            onValueChange={(value) => {
              const state = WORK_ITEM_STATES.find((each) => each === value);

              setTo(state ?? null);
            }}
          >
            <SelectTrigger
              size="sm"
              className="w-40"
              aria-label={t("New state")}
            >
              <SelectValue placeholder={t("Set state")} />
            </SelectTrigger>
            <SelectContent>
              {stateItems.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button
            size="sm"
            disabled={to === null || bulk.pending}
            onClick={() => {
              if (to !== null) {
                void run({ action: "state", to });
              }
            }}
          >
            {t("Apply")}
          </Button>
          <AlertDialog
            open={confirming}
            onOpenChange={(next) => {
              if (!bulk.pending) {
                setConfirming(next);
              }
            }}
          >
            <AlertDialogTrigger
              render={
                <Button
                  type="button"
                  size="sm"
                  variant="destructive"
                  disabled={bulk.pending}
                />
              }
            >
              <Trash2Icon />
              {t("Delete")}
            </AlertDialogTrigger>
            <AlertDialogContent>
              <AlertDialogHeader>
                <AlertDialogTitle>
                  {t(
                    "{count, plural, one {Delete # item?} other {Delete # items?}}",
                    { count: selected.length },
                  )}
                </AlertDialogTitle>
                <AlertDialogDescription>
                  {t("They move to the trash, where they can be restored.")}
                </AlertDialogDescription>
              </AlertDialogHeader>
              <AlertDialogFooter>
                <AlertDialogCancel disabled={bulk.pending}>
                  {t("Cancel")}
                </AlertDialogCancel>
                <AlertDialogAction
                  type="button"
                  variant="destructive"
                  disabled={bulk.pending}
                  onClick={() => {
                    void run({ action: "delete" }).then(() => {
                      setConfirming(false);
                    });
                  }}
                >
                  {t("Delete")}
                </AlertDialogAction>
              </AlertDialogFooter>
            </AlertDialogContent>
          </AlertDialog>
          <Button
            size="sm"
            variant="ghost"
            disabled={bulk.pending}
            onClick={() => {
              onSettled([]);
            }}
          >
            <XIcon />
            {t("Clear")}
          </Button>
        </div>
      )}
      {failures.length === 0 ? null : (
        <Alert variant="destructive">
          <TriangleAlertIcon />
          <AlertTitle>
            {t(
              "{count, plural, one {# item wasn't changed} other {# items weren't changed}}",
              { count: failures.length },
            )}
          </AlertTitle>
          <AlertDescription>
            <ul className="flex flex-col gap-1">
              {failures.map((failure) => (
                <li key={failure.id}>
                  <span className="font-medium tabular-nums">
                    {failure.identifier}
                  </span>
                  {": "}
                  {failure.message}
                </li>
              ))}
            </ul>
          </AlertDescription>
          <AlertAction>
            <Button
              size="sm"
              variant="outline"
              onClick={() => {
                setFailures([]);
              }}
            >
              {t("Dismiss")}
            </Button>
          </AlertAction>
        </Alert>
      )}
    </div>
  );
}
// #endregion recipe:bulk-action-bar
