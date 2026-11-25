"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

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
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";

import { addControlEvidence } from "../compliance-actions";

/**
 * Records a note as evidence on a control. With `task` the note answers that
 * evidence task and moves its due date.
 */
export function AddEvidenceDialog({
  controlId,
  task,
}: {
  controlId: string;
  task?: { readonly id: string; readonly title: string };
}) {
  const t = useExtracted("compliance");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(addControlEvidence, {
    onSuccess: () => {
      toast.success(t("Evidence added"));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        {task ? t("Collect") : t("Add evidence")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <input type="hidden" name="controlId" value={controlId} />
          {task ? (
            <input type="hidden" name="evidenceTaskId" value={task.id} />
          ) : null}
          <DialogHeader>
            <DialogTitle>{task ? task.title : t("Add evidence")}</DialogTitle>
            <DialogDescription>
              {task
                ? t("The note answers this task and moves its due date.")
                : t("The note counts as evidence until it is removed.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-note`}>{t("Note")}</FieldLabel>
              <Textarea
                id={`${fieldId}-note`}
                name="note"
                required
                maxLength={4000}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Add evidence")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
