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
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { createWorkOrder } from "../field-actions";

/** A dialog that opens a work order in the backlog. */
export function NewWorkOrderDialog() {
  const t = useExtracted("field");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createWorkOrder, {
    onSuccess: () => {
      setOpen(false);
      toast.success(t("Work order added to the backlog"));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant="outline" />}>
        <PlusIcon />
        {t("New work order")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New work order")}</DialogTitle>
            <DialogDescription>
              {t("It waits in the backlog until you schedule it.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={form.fieldErrors["title"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Job")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                aria-invalid={form.fieldErrors["title"] ? true : undefined}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-address`}>
                {t("Address")}
              </FieldLabel>
              <Input id={`${fieldId}-address`} name="address" maxLength={500} />
            </Field>
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Add")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
