"use client";

import { useAction, useActionForm } from "better-supabase/react";
import {
  BadgeCheckIcon,
  DownloadIcon,
  EllipsisIcon,
  PencilIcon,
  Share2Icon,
  Trash2Icon,
} from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogClose,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useUndoToast } from "@/features/trash/components/undo-toast";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  downloadDriveFile,
  renameDriveItem,
  requestDriveApproval,
  trashDriveItem,
} from "../drive-actions";
import { GrantsEditor, useDriveSharing } from "./grants-editor";

export function DriveItemActions({
  id,
  kind,
  name,
}: {
  id: string;
  kind: "folder" | "file";
  name: string;
}) {
  const t = useExtracted("drive");
  const errorMessage = useErrorMessage();
  const showUndo = useUndoToast();
  const [renaming, setRenaming] = useState(false);
  const [sharing, setSharing] = useState(false);
  const sharingLoad = useDriveSharing(id);

  const trash = useAction(trashDriveItem, {
    onSuccess: ({ trashItemId }) => {
      showUndo({ trashItemId, name });
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const download = useAction(downloadDriveFile, {
    onSuccess: ({ url }) => {
      window.location.assign(url);
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const approval = useAction(requestDriveApproval, {
    onSuccess: () => {
      toast.success(t("Approval requested for {name}", { name }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <>
      <DropdownMenu>
        <DropdownMenuTrigger
          render={
            <Button
              size="icon-sm"
              variant="ghost"
              disabled={trash.pending}
              aria-label={t("Actions for {name}", { name })}
            />
          }
        >
          <EllipsisIcon />
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          {kind === "file" ? (
            <DropdownMenuItem
              disabled={download.pending}
              onClick={() => {
                void download.run({ id });
              }}
            >
              <DownloadIcon />
              {t("Download")}
            </DropdownMenuItem>
          ) : null}
          {kind === "file" ? (
            <DropdownMenuItem
              disabled={approval.pending}
              onClick={() => {
                void approval.run({ id });
              }}
            >
              <BadgeCheckIcon />
              {t("Request approval")}
            </DropdownMenuItem>
          ) : null}
          <DropdownMenuItem
            onClick={() => {
              setRenaming(true);
            }}
          >
            <PencilIcon />
            {t("Rename")}
          </DropdownMenuItem>
          <DropdownMenuItem
            onClick={() => {
              setSharing(true);
              sharingLoad.open();
            }}
          >
            <Share2Icon />
            {t("Share")}
          </DropdownMenuItem>
          <DropdownMenuSeparator />
          <DropdownMenuItem
            variant="destructive"
            onClick={() => {
              void trash.run({ id });
            }}
          >
            <Trash2Icon />
            {t("Move to trash")}
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>
      <RenameDialog
        id={id}
        name={name}
        open={renaming}
        onOpenChange={setRenaming}
      />
      <GrantsEditor
        id={id}
        name={name}
        load={sharingLoad}
        open={sharing}
        onOpenChange={setSharing}
      />
    </>
  );
}

function RenameDialog({
  id,
  name,
  open,
  onOpenChange,
}: {
  id: string;
  name: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const t = useExtracted("drive");
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const form = useActionForm(renameDriveItem, {
    onSuccess: (item) => {
      onOpenChange(false);
      toast.success(t("Renamed to {name}", { name: item.name }));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Rename {name}", { name })}</DialogTitle>
          </DialogHeader>
          <input type="hidden" name="id" value={id} />
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-rename`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-rename`}
                name="name"
                defaultValue={name}
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
              {t("Rename")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
