"use client";

import { useActionForm } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
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
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { createProject } from "../project-actions";

/** Creates a project by name, so the first task has somewhere to go. */
export function ProjectFormDialog({
  variant = "outline",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("projects");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createProject, {
    onSuccess: () => {
      toast.success(t("Project created"));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          form.reset();
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" variant={variant} />}>
        <PlusIcon />
        {t("New project")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New project")}</DialogTitle>
            <DialogDescription>
              {t("Add its tasks once it exists.")}
            </DialogDescription>
          </DialogHeader>
          <Field data-invalid={error ? true : undefined}>
            <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
            <Input
              id={`${fieldId}-name`}
              name="name"
              required
              maxLength={200}
              autoComplete="off"
            />
            {error ? <FieldError>{error}</FieldError> : null}
          </Field>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create project")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
