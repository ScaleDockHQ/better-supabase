"use client";

import { useAction } from "better-supabase/react";
import { DownloadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useState } from "react";
import { toast } from "sonner";

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
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  cancelOrganizationDeletion,
  downloadExport,
  requestMyExport,
  requestOrganizationDeletion,
  requestOrganizationExport,
} from "../privacy-actions";

export function RequestExportButton({
  scope,
  variant = "default",
}: {
  scope: "user" | "organization";
  variant?: "default" | "outline";
}) {
  const t = useExtracted("privacy");
  const errorMessage = useErrorMessage();

  const options = {
    onSuccess: () => {
      toast.success(t("Export ready to download"));
    },
    onError: (error: Parameters<typeof errorMessage>[0]) => {
      toast.error(errorMessage(error));
    },
  };

  const mine = useAction(requestMyExport, options);
  const organization = useAction(requestOrganizationExport, options);
  const pending = mine.pending || organization.pending;

  return (
    <Button
      type="button"
      variant={variant}
      disabled={pending}
      onClick={() => {
        void (scope === "user"
          ? mine.run(undefined)
          : organization.run(undefined));
      }}
    >
      {pending ? t("Exporting…") : t("Export data")}
    </Button>
  );
}

export function DownloadExportButton({ id }: { id: string }) {
  const t = useExtracted("privacy");
  const errorMessage = useErrorMessage();

  const [files, setFiles] = useState<
    readonly { readonly table: string; readonly url: string }[] | null
  >(null);

  const download = useAction(downloadExport, {
    onSuccess: (data) => {
      setFiles(data);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        disabled={download.pending}
        onClick={() => {
          void download.run({ id });
        }}
      >
        <DownloadIcon />
        {t("Download")}
      </Button>
      <Dialog
        open={files !== null}
        onOpenChange={(open) => {
          if (!open) {
            setFiles(null);
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{t("Download your export")}</DialogTitle>
            <DialogDescription>
              {t(
                "One file per table, one JSON object per line. The links work for five minutes.",
              )}
            </DialogDescription>
          </DialogHeader>
          <ul className="flex max-h-80 flex-col gap-1 overflow-y-auto">
            {(files ?? []).map((file) => (
              <li key={file.table}>
                <a
                  href={file.url}
                  className="font-mono text-xs text-foreground underline-offset-4 transition-colors hover:text-primary hover:underline"
                >
                  {file.table}
                </a>
              </li>
            ))}
          </ul>
        </DialogContent>
      </Dialog>
    </>
  );
}

export function DeleteOrganizationButton() {
  const t = useExtracted("privacy");
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const request = useAction(requestOrganizationDeletion, {
    onSuccess: () => {
      setOpen(false);
      toast.success(
        t("Deletion scheduled. You can cancel it until the purge."),
      );
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <AlertDialog
      open={open}
      onOpenChange={(next) => {
        if (!request.pending) {
          setOpen(next);
        }
      }}
    >
      <AlertDialogTrigger
        render={<Button type="button" variant="destructive" />}
      >
        {t("Delete organization")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("Delete this organization?")}</AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "Members lose access right away. Its data is purged after 30 days unless an owner cancels before then.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={request.pending}>
            {t("Cancel")}
          </AlertDialogCancel>
          <AlertDialogAction
            type="button"
            variant="destructive"
            disabled={request.pending}
            onClick={() => {
              void request.run(undefined);
            }}
          >
            {t("Delete organization")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

export function CancelDeletionButton() {
  const t = useExtracted("privacy");
  const errorMessage = useErrorMessage();

  const cancel = useAction(cancelOrganizationDeletion, {
    onSuccess: () => {
      toast.success(t("Deletion cancelled"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      type="button"
      variant="outline"
      size="sm"
      disabled={cancel.pending}
      onClick={() => {
        void cancel.run(undefined);
      }}
    >
      {t("Cancel deletion")}
    </Button>
  );
}
