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
import { useErrorMessage } from "@/lib/use-error-message";

import { createEmployee } from "../people-actions";

interface Option {
  readonly value: string;
  readonly label: string;
}

export function AddEmployeeDialog({
  managers,
  canViewSensitive,
}: {
  managers: readonly Option[];
  canViewSensitive: boolean;
}) {
  const t = useExtracted("people");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createEmployee, {
    onSuccess: (employee) => {
      setOpen(false);
      toast.success(t("{name} added", { name: employee.name }));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);
  const managerItems = [{ value: "", label: t("No manager") }, ...managers];

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button />}>
        <PlusIcon />
        {t("Add employee")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add employee")}</DialogTitle>
            <DialogDescription>
              {t("They start as preboarding until their start date.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={form.fieldErrors["name"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={200}
                aria-invalid={form.fieldErrors["name"] ? true : undefined}
              />
            </Field>
            <Field data-invalid={form.fieldErrors["email"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-email`}>
                {t("Work email")}
              </FieldLabel>
              <Input
                id={`${fieldId}-email`}
                name="email"
                type="email"
                aria-invalid={form.fieldErrors["email"] ? true : undefined}
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-title`}>
                {t("Job title")}
              </FieldLabel>
              <Input id={`${fieldId}-title`} name="jobTitle" maxLength={200} />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-manager`}>
                {t("Manager")}
              </FieldLabel>
              <Select name="managerId" items={managerItems} defaultValue="">
                <SelectTrigger id={`${fieldId}-manager`} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {managerItems.map((item) => (
                    <SelectItem key={item.value} value={item.value}>
                      {item.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-start`}>
                {t("Start date")}
              </FieldLabel>
              <Input id={`${fieldId}-start`} name="startDate" type="date" />
            </Field>
            {canViewSensitive ? (
              <>
                <Field>
                  <FieldLabel htmlFor={`${fieldId}-phone`}>
                    {t("Phone")}
                  </FieldLabel>
                  <Input
                    id={`${fieldId}-phone`}
                    name="phone"
                    type="tel"
                    maxLength={50}
                  />
                  <FieldDescription>
                    {t(
                      "Private: only people who can see sensitive fields read it.",
                    )}
                  </FieldDescription>
                </Field>
                <Field
                  data-invalid={
                    form.fieldErrors["personalEmail"] ? true : undefined
                  }
                >
                  <FieldLabel htmlFor={`${fieldId}-personal-email`}>
                    {t("Personal email")}
                  </FieldLabel>
                  <Input
                    id={`${fieldId}-personal-email`}
                    name="personalEmail"
                    type="email"
                    aria-invalid={
                      form.fieldErrors["personalEmail"] ? true : undefined
                    }
                  />
                </Field>
              </>
            ) : null}
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
