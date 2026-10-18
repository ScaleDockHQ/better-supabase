"use client";

import type { JsonPatchOperation } from "better-supabase/blocks/versions";

import { useAction } from "better-supabase/react";
import { HistoryIcon, TriangleAlertIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { toast } from "sonner";

import {
  Alert,
  AlertAction,
  AlertDescription,
  AlertTitle,
} from "@/components/reui/alert";
import { Badge } from "@/components/reui/badge";
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
  Card,
  CardAction,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Skeleton } from "@/components/ui/skeleton";
import { useErrorMessage } from "@/lib/use-error-message";

import type { Loaded, VersionRow } from "../customer-record-queries";

import {
  compareCustomerVersions,
  restoreCustomerVersion,
  saveCustomerVersion,
} from "../customer-record-actions";
import { RecordCardSkeleton, RecordLoadError } from "./record-card-states";

// #region recipe:version-history

/**
 * Saved versions of the customer's name and KvK number, newest first. Each
 * one compares with the version before it and restores as a new version.
 */
export function VersionHistory({
  customerId,
  versions,
  canSave,
  canRestore,
}: {
  customerId: string;
  versions: Loaded<readonly VersionRow[]>;
  canSave: boolean;
  canRestore: boolean;
}) {
  const t = useExtracted("customers");

  return (
    <Card size="sm" data-recipe="version-history">
      <CardHeader>
        <CardTitle>{t("Version history")}</CardTitle>
        <CardDescription>
          {t("Snapshots of the name and KvK number.")}
        </CardDescription>
        {canSave && versions.kind === "ok" && versions.data.length > 0 ? (
          <CardAction>
            <SaveVersionButton customerId={customerId} />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {versions.kind === "error" ? (
          <RecordLoadError title={t("The versions didn't load")} />
        ) : versions.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <HistoryIcon />
              </EmptyMedia>
              <EmptyTitle>{t("No versions yet")}</EmptyTitle>
              <EmptyDescription>
                {t(
                  "Save a version to keep the customer's details as they are now.",
                )}
              </EmptyDescription>
            </EmptyHeader>
            {canSave ? (
              <EmptyContent>
                <SaveVersionButton customerId={customerId} />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <VersionList
            customerId={customerId}
            versions={versions.data}
            canRestore={canRestore}
          />
        )}
      </CardContent>
    </Card>
  );
}

function VersionList({
  customerId,
  versions,
  canRestore,
}: {
  customerId: string;
  versions: readonly VersionRow[];
  canRestore: boolean;
}) {
  const t = useExtracted("customers");
  const format = useFormatter();

  const source = {
    manual: t("Saved"),
    auto: t("Automatic"),
    restore: t("Restored"),
  } as const satisfies Record<VersionRow["source"], string>;

  return (
    <ol className="flex flex-col divide-y" data-testid="versions">
      {versions.map((version, index) => {
        const previous = versions[index + 1];

        return (
          <li
            key={version.id}
            className="flex items-center justify-between gap-2 py-2"
          >
            <div className="flex min-w-0 flex-col gap-1">
              <div className="flex items-center gap-2">
                <span className="text-sm font-medium">
                  {t("Version {number}", { number: String(version.number) })}
                </span>
                <Badge variant="secondary">{source[version.source]}</Badge>
              </div>
              <span className="truncate text-xs text-muted-foreground">
                {version.label ? `${version.label} · ` : ""}
                {format.dateTime(version.createdAt, {
                  dateStyle: "medium",
                  timeStyle: "short",
                })}
              </span>
            </div>
            <div className="flex items-center gap-1">
              {previous ? (
                <CompareDialog
                  fromId={previous.id}
                  toId={version.id}
                  fromNumber={previous.number}
                  toNumber={version.number}
                />
              ) : null}
              {canRestore && index > 0 ? (
                <RestoreButton
                  customerId={customerId}
                  versionId={version.id}
                  number={version.number}
                />
              ) : null}
            </div>
          </li>
        );
      })}
    </ol>
  );
}

function SaveVersionButton({ customerId }: { customerId: string }) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();

  const save = useAction(saveCustomerVersion, {
    onSuccess: () => {
      toast.success(t("Version saved"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={save.pending}
      onClick={() => {
        void save.run({ customerId });
      }}
    >
      <HistoryIcon />
      {t("Save a version")}
    </Button>
  );
}

function CompareDialog({
  fromId,
  toId,
  fromNumber,
  toNumber,
}: {
  fromId: string;
  toId: string;
  fromNumber: number;
  toNumber: number;
}) {
  const t = useExtracted("customers");
  const compare = useAction(compareCustomerVersions);

  const load = () => {
    void compare.run({ fromId, toId });
  };

  return (
    <Dialog
      onOpenChange={(open) => {
        if (open) {
          load();
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" variant="ghost" />}>
        {t("Compare")}
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>
            {t("Version {from} to {to}", {
              from: String(fromNumber),
              to: String(toNumber),
            })}
          </DialogTitle>
          <DialogDescription>
            {t("What changed between the two versions.")}
          </DialogDescription>
        </DialogHeader>
        {compare.error ? (
          <Alert variant="destructive">
            <TriangleAlertIcon />
            <AlertTitle>{t("The comparison didn't load")}</AlertTitle>
            <AlertDescription>{t("Try again in a moment.")}</AlertDescription>
            <AlertAction>
              <Button size="sm" variant="outline" onClick={load}>
                {t("Retry")}
              </Button>
            </AlertAction>
          </Alert>
        ) : compare.data === undefined || compare.pending ? (
          <div className="flex flex-col gap-2">
            <Skeleton className="h-8" />
            <Skeleton className="h-8" />
          </div>
        ) : compare.data.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            {t("The two versions are the same.")}
          </p>
        ) : (
          <ul className="flex flex-col divide-y" data-testid="version-diff">
            {compare.data.map((operation) => (
              <li
                key={`${operation.op}:${operation.path}`}
                className="flex items-center gap-2 py-2 text-sm"
              >
                <ChangeBadge operation={operation} />
                <code className="text-xs">{operation.path}</code>
                {"value" in operation ? (
                  <span className="truncate">
                    {JSON.stringify(operation.value)}
                  </span>
                ) : null}
              </li>
            ))}
          </ul>
        )}
        <DialogFooter>
          <DialogClose render={<Button />}>{t("Done")}</DialogClose>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ChangeBadge({ operation }: { operation: JsonPatchOperation }) {
  const t = useExtracted("customers");

  switch (operation.op) {
    case "add": {
      return <Badge variant="success-light">{t("Added")}</Badge>;
    }

    case "remove": {
      return <Badge variant="destructive-light">{t("Removed")}</Badge>;
    }

    case "replace": {
      return <Badge variant="info-light">{t("Changed")}</Badge>;
    }

    case "move":
    case "copy":
    case "test": {
      return <Badge variant="secondary">{operation.op}</Badge>;
    }

    default: {
      const unhandled: never = operation;

      return unhandled;
    }
  }
}

function RestoreButton({
  customerId,
  versionId,
  number,
}: {
  customerId: string;
  versionId: string;
  number: number;
}) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();

  const restore = useAction(restoreCustomerVersion, {
    onSuccess: () => {
      toast.success(t("Version restored"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={<Button size="sm" variant="ghost" disabled={restore.pending} />}
      >
        {t("Restore")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            {t("Restore version {number}?", { number: String(number) })}
          </AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "The customer's name and KvK number go back to this version. The current details stay in the history.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
          <AlertDialogAction
            onClick={() => {
              void restore.run({ customerId, versionId });
            }}
          >
            {t("Restore")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

/** The version history card while its rows load. */
export function VersionHistorySkeleton() {
  return <RecordCardSkeleton rows={3} />;
}

// #endregion recipe:version-history
