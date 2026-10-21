"use client";

import type { ChangeEvent } from "react";

import { useAction } from "better-supabase/react";
import { DownloadIcon, PaperclipIcon, UploadIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useRef, useState } from "react";
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
import { useSupabase } from "@/lib/hooks";
import { useErrorMessage } from "@/lib/use-error-message";

import type { AttachmentRow, Loaded } from "../customer-record-queries";

import {
  confirmAttachment,
  downloadAttachment,
  removeAttachment,
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
 * Files on the customer, in the private `attachments` bucket. The server
 * records each file and signs a one-time upload; the browser sends the bytes. A
 * file downloads once the scanner marked it clean.
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

  return (
    <Card size="sm" data-recipe="attachments-uploader">
      <CardHeader>
        <CardTitle>{t("Files")}</CardTitle>
        <CardDescription>
          {t("Files download after the virus scan marks them clean.")}
        </CardDescription>
        {canUpload && files.kind === "ok" && files.data.length > 0 ? (
          <CardAction>
            <UploadButton customerId={customerId} />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {files.kind === "error" ? (
          <RecordLoadError title={t("The files didn't load")} />
        ) : files.data.length === 0 ? (
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
                <UploadButton customerId={customerId} />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <FileList
            customerId={customerId}
            files={files.data}
            canRemove={canRemove}
          />
        )}
      </CardContent>
    </Card>
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

function UploadButton({ customerId }: { customerId: string }) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();
  const supabase = useSupabase();
  const input = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);

  const start = useAction(startAttachmentUpload);
  const confirm = useAction(confirmAttachment);

  const upload = async (file: File) => {
    const started = await start.run({
      customerId,
      name: file.name,
      mimeType: file.type,
      size: file.size,
    });

    if (!started.ok) {
      toast.error(errorMessage(started.error));

      return;
    }

    const { id, bucket, path, token } = started.data;

    const sent = await supabase.storage
      .from(bucket)
      .uploadToSignedUrl(path, token, file, { contentType: file.type });

    if (sent.error) {
      toast.error(t("The upload failed. Try again."));

      return;
    }

    const confirmed = await confirm.run({ id });

    if (confirmed.ok) {
      toast.success(t("File uploaded"));
    } else {
      toast.error(errorMessage(confirmed.error));
    }
  };

  const pick = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    event.target.value = "";

    if (!file) {
      return;
    }

    setUploading(true);
    void upload(file).finally(() => {
      setUploading(false);
    });
  };

  return (
    <>
      <input
        ref={input}
        type="file"
        className="sr-only"
        tabIndex={-1}
        aria-hidden
        onChange={pick}
      />
      <Button
        size="sm"
        disabled={uploading}
        onClick={() => input.current?.click()}
      >
        <UploadIcon />
        {uploading ? t("Uploading") : t("Upload file")}
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

  const remove = useAction(removeAttachment, {
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
              void remove.run({ id, customerId });
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
