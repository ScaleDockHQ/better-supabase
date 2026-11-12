"use client";

import type { DbError } from "better-supabase";
import type { SubmitEvent } from "react";

import { ArchiveIcon, PencilIcon, PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState, useTransition } from "react";

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
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  archiveOptionItem,
  editOptionItem,
  ensureOptionSet,
} from "../option-sets-actions";

/** Creates the default priority set of tasks, the one field the example binds. */
export function EnsurePrioritySetButton({
  variant = "default",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("optionSets");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      variant={variant}
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const ensured = await ensureOptionSet({
            subjectType: "work_item",
            field: "priority",
          });

          if (ensured.ok) {
            toast.success(t("Priority options created"));
          } else {
            toast.error(errorMessage(ensured.error));
          }
        });
      }}
    >
      <PlusIcon />
      {t("Create task priorities")}
    </Button>
  );
}

/** The label and color of one item. */
export function EditOptionItemDialog({
  setId,
  itemId,
  label,
  color,
}: {
  setId: string;
  itemId: string;
  label: string;
  color: string | null;
}) {
  const t = useExtracted("optionSets");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<DbError>();
  const [pending, startTransition] = useTransition();
  const message = error === undefined ? null : errorMessage(error);

  const submit = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);

    startTransition(async () => {
      const saved = await editOptionItem({
        setId,
        itemId,
        label: String(form.get("label") ?? ""),
        color: String(form.get("color") ?? ""),
      });

      if (!saved.ok) {
        setError(saved.error);

        return;
      }

      setError(undefined);
      setOpen(false);
      toast.success(t("Option saved"));
    });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setError(undefined);
      }}
    >
      <DialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={t("Edit {label}", { label })}
          />
        }
      >
        <PencilIcon />
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Edit option")}</DialogTitle>
            <DialogDescription>
              {t(
                "Records keep the option's level, so sorting and reports stay the same.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={message ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-label`}>{t("Label")}</FieldLabel>
              <Input
                id={`${fieldId}-label`}
                name="label"
                required
                maxLength={200}
                defaultValue={label}
              />
              {message ? <FieldError>{message}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-color`}>{t("Color")}</FieldLabel>
              <Input
                id={`${fieldId}-color`}
                name="color"
                maxLength={50}
                defaultValue={color ?? ""}
                placeholder="red"
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={pending}>
              {t("Save")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Archives one item; an item records still use is refused. */
export function ArchiveOptionItemButton({
  itemId,
  label,
}: {
  itemId: string;
  label: string;
}) {
  const t = useExtracted("optionSets");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={
          <Button
            variant="ghost"
            size="icon-sm"
            disabled={pending}
            aria-label={t("Archive {label}", { label })}
          />
        }
      >
        <ArchiveIcon />
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>
            {t("Archive {label}?", { label })}
          </AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "New records can no longer pick it. An option that records still use can't be archived until they move to another option.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={pending}
            onClick={() => {
              startTransition(async () => {
                const archived = await archiveOptionItem({ itemId });

                if (archived.ok) {
                  toast.success(t("Option archived"));
                } else {
                  toast.error(errorMessage(archived.error));
                }
              });
            }}
          >
            {t("Archive")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
