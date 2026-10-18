"use client";

import { useAction, useActionForm } from "better-supabase/react";
import { FolderPlusIcon, UploadIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useRef, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
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
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useSupabase } from "@/lib/hooks";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  abandonDriveUpload,
  commitDriveUpload,
  createDriveFolder,
  startDriveUpload,
} from "../drive-actions";

export function CreateFolderDialog({ parentId }: { parentId: string | null }) {
  const t = useExtracted("drive");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createDriveFolder, {
    onSuccess: (folder) => {
      setOpen(false);
      toast.success(t("{name} created", { name: folder.name }));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant="outline" />}>
        <FolderPlusIcon />
        {t("New folder")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New folder")}</DialogTitle>
            <DialogDescription>
              {t(
                "The folder is created here. A taken name gets a number added.",
              )}
            </DialogDescription>
          </DialogHeader>
          <input type="hidden" name="parentId" value={parentId ?? ""} />
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-folder-name`}>
                {t("Name")}
              </FieldLabel>
              <Input
                id={`${fieldId}-folder-name`}
                name="name"
                placeholder={t("Untitled folder")}
                required
                maxLength={255}
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/**
 * Uploads the picked file as soon as it is chosen: the server creates the
 * node and a signed URL, the browser sends the bytes to Storage, and the
 * server commits them.
 */
export function UploadFileButton({ parentId }: { parentId: string | null }) {
  const t = useExtracted("drive");
  const errorMessage = useErrorMessage();
  const supabase = useSupabase();
  const inputRef = useRef<HTMLInputElement>(null);
  const [sending, setSending] = useState(false);

  const start = useAction(startDriveUpload);
  const commit = useAction(commitDriveUpload);
  const abandon = useAction(abandonDriveUpload);
  const pending = sending || start.pending || commit.pending;

  async function upload(file: File) {
    const started = await start.run({
      parentId,
      name: file.name,
      mimeType: file.type,
      size: file.size,
    });

    if (!started.ok) {
      toast.error(errorMessage(started.error));

      return;
    }

    const { nodeId, attachmentId, bucket, path, token } = started.data;
    setSending(true);

    const sent = await supabase.storage
      .from(bucket)
      .uploadToSignedUrl(path, token, file, {
        contentType: file.type || "application/octet-stream",
      });

    setSending(false);

    if (sent.error) {
      await abandon.run({ nodeId });
      toast.error(t("{name} didn't upload. Try again.", { name: file.name }));

      return;
    }

    const committed = await commit.run({ nodeId, attachmentId });

    if (committed.ok) {
      toast.success(t("{name} uploaded", { name: committed.data.name }));
    } else {
      toast.error(errorMessage(committed.error));
    }
  }

  return (
    <>
      <input
        ref={inputRef}
        type="file"
        className="sr-only"
        tabIndex={-1}
        aria-label={t("File to upload")}
        onChange={(event) => {
          const file = event.currentTarget.files?.[0];
          event.currentTarget.value = "";

          if (file) {
            void upload(file);
          }
        }}
      />
      <Button
        type="button"
        disabled={pending}
        onClick={() => {
          inputRef.current?.click();
        }}
      >
        <UploadIcon />
        {pending ? t("Uploading") : t("Upload file")}
      </Button>
    </>
  );
}
