"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { PlusIcon } from "lucide-react";
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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { toast } from "@/lib/toast";

import { requestLeave } from "../leave-actions";

export function RequestLeaveDialog({
  types,
}: {
  types: readonly { readonly id: string; readonly name: string }[];
}) {
  const t = useExtracted("people");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(requestLeave, {
    onSuccess: (request) => {
      setOpen(false);
      toast.success(
        t("Leave requested for {amount} days", {
          amount: String(request.amount),
        }),
      );
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  const partials = [
    { value: "full", label: t("Whole days") },
    { value: "morning", label: t("Morning") },
    { value: "afternoon", label: t("Afternoon") },
  ];

  const typeItems = types.map((type) => ({ value: type.id, label: type.name }));

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button disabled={types.length === 0} />}>
        <PlusIcon />
        {t("Request leave")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Request leave")}</DialogTitle>
            <DialogDescription>
              {t(
                "A manager approves the request. Working days are counted for you.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={form.fieldErrors["typeId"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-type`}>{t("Type")}</FieldLabel>
              <Select
                name="typeId"
                items={typeItems}
                defaultValue={typeItems[0]?.value}
              >
                <SelectTrigger id={`${fieldId}-type`} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {typeItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <div className="grid grid-cols-2 gap-4">
              <Field
                data-invalid={form.fieldErrors["startsOn"] ? true : undefined}
              >
                <FieldLabel htmlFor={`${fieldId}-from`}>{t("From")}</FieldLabel>
                <Input
                  id={`${fieldId}-from`}
                  name="startsOn"
                  type="date"
                  required
                />
              </Field>
              <Field
                data-invalid={form.fieldErrors["endsOn"] ? true : undefined}
              >
                <FieldLabel htmlFor={`${fieldId}-to`}>{t("To")}</FieldLabel>
                <Input id={`${fieldId}-to`} name="endsOn" type="date" />
                <FieldDescription>
                  {t("Leave empty for one day.")}
                </FieldDescription>
              </Field>
            </div>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-part`}>
                {t("Part of the day")}
              </FieldLabel>
              <Select name="partial" items={partials} defaultValue="full">
                <SelectTrigger id={`${fieldId}-part`} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {partials.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-note`}>{t("Note")}</FieldLabel>
              <Input id={`${fieldId}-note`} name="note" maxLength={500} />
            </Field>
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button variant="outline" type="button" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Request")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
