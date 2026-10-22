"use client";

import type {
  AttachmentFileInput,
  AttachmentUploadItem,
  AttachmentUploadState,
} from "better-supabase/blocks/attachments/react";
import type { ChangeEvent, ReactNode } from "react";

import { useAttachmentUpload } from "better-supabase/blocks/attachments/react";
import { useAction } from "better-supabase/react";
import {
  DownloadIcon,
  PaperclipIcon,
  RotateCwIcon,
  UploadIcon,
  XIcon,
} from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useEffect, useEffectEvent, useRef, useState } from "react";
import { toast } from "sonner";

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
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Progress } from "@/components/ui/progress";
import { removeCustomerAttachments } from "@/lib/supabase/features/customer/customer-actions";
import { useErrorMessage } from "@/lib/use-error-message";

import type { AttachmentRow, Loaded } from "../customer-record-queries";

import {
  confirmAttachment,
  downloadAttachment,
  startAttachmentUpload,
} from "../customer-record-actions";
import { RecordCardSkeleton, RecordLoadError } from "./record-card-states";

// #region recipe:attachments-uploader

type FileState = "unfinished" | "scanning" | "ready" | "blocked" | "failed";

function stateOf(file: AttachmentRow): FileState {
  switch (file.status) {
    case "pending": {
      return file.uploaded ? "scanning" : "unfinished";
    }

    case "clean": {
      return "ready";
    }

    case "infected": {
      return "blocked";
    }

    case "failed": {
      return "failed";
    }

    default: {
      const unhandled: never = file.status;

      return unhandled;
    }
  }
}

const VARIANT = {
  unfinished: "warning-light",
  scanning: "info-light",
  ready: "success-light",
  blocked: "destructive-light",
  failed: "destructive-light",
} as const satisfies Record<FileState, string>;

/**
 * Files on the customer, in the private `attachments` bucket. Pick, drop or
 * paste files: the server records each one and signs its upload,
 * `useAttachmentUpload` sends the bytes with progress, and the server confirms
 * it. A file downloads once the scanner marked it clean.
 */
export function AttachmentsUploader({
  customerId,
  files,
  canUpload,
  canRemove,
}: {
  customerId: string;
  files: Loaded<readonly AttachmentRow[]>;
  canUpload: boolean;
  canRemove: boolean;
}) {
  const t = useExtracted("customers");
  const upload = useCustomerUpload(customerId);

  return (
    <Card size="sm" data-recipe="attachments-uploader">
      <CardHeader>
        <CardTitle>{t("Files")}</CardTitle>
        <CardDescription>
          {canUpload
            ? t(
                "Drop or paste files to upload. They download after the virus scan.",
              )
            : t("Files download after the virus scan marks them clean.")}
        </CardDescription>
        {canUpload && files.kind === "ok" && files.data.length > 0 ? (
          <CardAction>
            <UploadButton busy={upload.busy} onPick={upload.add} />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        <DropZone enabled={canUpload} onFiles={upload.add}>
          {upload.uploads.length > 0 ? <UploadList upload={upload} /> : null}
          {files.kind === "error" ? (
            <RecordLoadError title={t("The files didn't load")} />
          ) : files.data.length === 0 ? (
            upload.uploads.length > 0 ? null : (
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <PaperclipIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("No files yet")}</EmptyTitle>
                  <EmptyDescription>
                    {t(
                      "Attach contracts, quotes or anything else about this customer.",
                    )}
                  </EmptyDescription>
                </EmptyHeader>
                {canUpload ? (
                  <EmptyContent>
                    <UploadButton busy={upload.busy} onPick={upload.add} />
                  </EmptyContent>
                ) : null}
              </Empty>
            )
          ) : (
            <FileList
              customerId={customerId}
              files={files.data}
              canRemove={canRemove}
            />
          )}
        </DropZone>
      </CardContent>
    </Card>
  );
}

/**
 * Uploads to the customer through the server actions, which check
 * `attachments.upload` and read the page again once a file is confirmed.
 */
function useCustomerUpload(customerId: string): AttachmentUploadState {
  const t = useExtracted("customers");
  const start = useAction(startAttachmentUpload);
  const confirm = useAction(confirmAttachment);

  return useAttachmentUpload({
    subject: { type: "customer", id: customerId },
    start: (file) =>
      start.run({
        customerId,
        name: file.name,
        mimeType: file.mimeType,
        size: file.size,
      }),
    confirm: (id) => confirm.run({ id }),
    refresh: false,
    onUploaded: () => {
      toast.success(t("File uploaded"));
    },
  });
}

const asInputs = (files: Iterable<File>): AttachmentFileInput[] =>
  [...files].map((file) => ({ file, name: file.name }));

const EDITABLE = "input, textarea, select, [contenteditable]";

/**
 * Takes files dropped on it and files pasted anywhere on the page outside a
 * text field; a plain wrapper when uploads are off. The Upload button is the
 * keyboard path, so the zone itself takes no focus.
 */
function DropZone({
  enabled,
  onFiles,
  children,
}: {
  enabled: boolean;
  onFiles: (files: readonly AttachmentFileInput[]) => void;
  children: ReactNode;
}) {
  const zone = useRef<HTMLDivElement>(null);
  const [dragging, setDragging] = useState(false);

  const take = useEffectEvent((files: FileList | null | undefined) => {
    const inputs = asInputs(files ?? []);

    if (inputs.length > 0) {
      onFiles(inputs);
    }
  });

  useEffect(() => {
    const element = zone.current;

    if (!enabled || !element) {
      return;
    }

    const over = (event: DragEvent) => {
      event.preventDefault();
      setDragging(true);
    };

    const leave = () => {
      setDragging(false);
    };

    const drop = (event: DragEvent) => {
      event.preventDefault();
      setDragging(false);
      take(event.dataTransfer?.files);
    };

    const paste = (event: ClipboardEvent) => {
      const files = event.clipboardData?.files;

      if (
        !files ||
        files.length === 0 ||
        (event.target instanceof Element && event.target.closest(EDITABLE))
      ) {
        return;
      }

      event.preventDefault();
      take(files);
    };

    element.addEventListener("dragover", over);
    element.addEventListener("dragleave", leave);
    element.addEventListener("drop", drop);
    document.addEventListener("paste", paste);

    return () => {
      element.removeEventListener("dragover", over);
      element.removeEventListener("dragleave", leave);
      element.removeEventListener("drop", drop);
      document.removeEventListener("paste", paste);
    };
  }, [enabled]);

  return (
    <div
      ref={zone}
      data-dragging={(enabled && dragging) || undefined}
      className="-m-2 flex flex-col gap-3 p-2 transition-colors data-dragging:bg-muted"
    >
      {children}
    </div>
  );
}

function UploadList({ upload }: { upload: AttachmentUploadState }) {
  return (
    <ul className="flex flex-col divide-y" data-testid="uploads">
      {upload.uploads.map((item) => (
        <UploadRow
          key={item.key}
          item={item}
          onRetry={upload.retry}
          onDismiss={upload.dismiss}
        />
      ))}
    </ul>
  );
}

const UPLOAD_VARIANT = {
  uploading: "info-light",
  confirming: "info-light",
  scanning: "info-light",
  done: "success-light",
  blocked: "destructive-light",
  error: "destructive-light",
} as const satisfies Record<AttachmentUploadItem["status"], string>;

function UploadRow({
  item,
  onRetry,
  onDismiss,
}: {
  item: AttachmentUploadItem;
  onRetry: (key: string) => void;
  onDismiss: (key: string) => void;
}) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();

  const label: Record<AttachmentUploadItem["status"], string> = {
    uploading: t("Uploading"),
    confirming: t("Saving"),
    scanning: t("Waiting for scan"),
    done: t("Uploaded"),
    blocked: t("Blocked"),
    error: t("Failed"),
  };

  return (
    <li className="flex items-center justify-between gap-2 py-2">
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <span className="truncate text-sm font-medium">{item.name}</span>
        <div className="flex items-center gap-2">
          <Badge variant={UPLOAD_VARIANT[item.status]}>
            {label[item.status]}
          </Badge>
          {item.status === "uploading" ? (
            <Progress
              className="flex-1"
              value={Math.round(item.progress * 100)}
              aria-label={t("Upload progress for {name}", { name: item.name })}
            />
          ) : item.error === undefined ? null : (
            <span className="truncate text-xs text-muted-foreground">
              {errorMessage(item.error)}
            </span>
          )}
        </div>
      </div>
      <div className="flex items-center gap-1">
        {item.status === "error" ? (
          <Button
            size="icon-sm"
            variant="ghost"
            aria-label={t("Retry {name}", { name: item.name })}
            onClick={() => {
              onRetry(item.key);
            }}
          >
            <RotateCwIcon />
          </Button>
        ) : null}
        <Button
          size="icon-sm"
          variant="ghost"
          aria-label={t("Dismiss {name}", { name: item.name })}
          onClick={() => {
            onDismiss(item.key);
          }}
        >
          <XIcon />
        </Button>
      </div>
    </li>
  );
}

function FileList({
  customerId,
  files,
  canRemove,
}: {
  customerId: string;
  files: readonly AttachmentRow[];
  canRemove: boolean;
}) {
  const t = useExtracted("customers");
  const format = useFormatter();
  const errorMessage = useErrorMessage();

  const label: Record<FileState, string> = {
    unfinished: t("Upload unfinished"),
    scanning: t("Waiting for scan"),
    ready: t("Ready"),
    blocked: t("Blocked"),
    failed: t("Scan failed"),
  };

  const download = useAction(downloadAttachment, {
    onSuccess: ({ signedUrl }) => {
      window.location.assign(signedUrl);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <ul className="flex flex-col divide-y" data-testid="attachments">
      {files.map((file) => {
        const state = stateOf(file);

        return (
          <li
            key={file.id}
            className="flex items-center justify-between gap-2 py-2"
          >
            <div className="flex min-w-0 flex-col gap-1">
              <span className="truncate text-sm font-medium">{file.name}</span>
              <div className="flex items-center gap-2">
                <Badge variant={VARIANT[state]}>{label[state]}</Badge>
                <span className="text-xs text-muted-foreground">
                  {format.number(file.size / 1024, {
                    style: "unit",
                    unit: "kilobyte",
                    maximumFractionDigits: 1,
                  })}
                </span>
              </div>
            </div>
            <div className="flex items-center gap-1">
              <Button
                size="icon-sm"
                variant="ghost"
                aria-label={t("Download {name}", { name: file.name })}
                disabled={state !== "ready" || download.pending}
                onClick={() => {
                  void download.run({ id: file.id });
                }}
              >
                <DownloadIcon />
              </Button>
              {canRemove ? (
                <RemoveFile
                  id={file.id}
                  customerId={customerId}
                  name={file.name}
                />
              ) : null}
            </div>
          </li>
        );
      })}
    </ul>
  );
}

function UploadButton({
  busy,
  onPick,
}: {
  busy: boolean;
  onPick: (files: readonly AttachmentFileInput[]) => void;
}) {
  const t = useExtracted("customers");
  const input = useRef<HTMLInputElement>(null);

  const pick = (event: ChangeEvent<HTMLInputElement>) => {
    const inputs = asInputs(event.target.files ?? []);
    event.target.value = "";

    if (inputs.length > 0) {
      onPick(inputs);
    }
  };

  return (
    <>
      <input
        ref={input}
        type="file"
        multiple
        className="sr-only"
        tabIndex={-1}
        aria-hidden
        onChange={pick}
      />
      <Button size="sm" onClick={() => input.current?.click()}>
        <UploadIcon />
        {busy ? t("Upload more") : t("Upload files")}
      </Button>
    </>
  );
}

function RemoveFile({
  id,
  customerId,
  name,
}: {
  id: string;
  customerId: string;
  name: string;
}) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();

  const remove = useAction(removeCustomerAttachments, {
    onSuccess: () => {
      toast.success(t("File removed"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={<Button size="sm" variant="ghost" disabled={remove.pending} />}
      >
        {t("Remove")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("Remove {name}?", { name })}</AlertDialogTitle>
          <AlertDialogDescription>
            {t("The file is deleted from storage. This can't be undone.")}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            onClick={() => {
              void remove.run({ id: customerId, input: { id } });
            }}
          >
            {t("Remove")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

/** The files card while its rows load. */
export function AttachmentsUploaderSkeleton() {
  return <RecordCardSkeleton rows={2} />;
}

// #endregion recipe:attachments-uploader
