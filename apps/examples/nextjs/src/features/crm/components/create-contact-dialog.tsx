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
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import { createContact } from "../crm-actions";
import { FormSelect } from "./form-select";

type Kind = "company" | "person";

/** Adds a company or a person, then opens it. */
export function CreateContactDialog({
  variant = "default",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("crm");
  const fieldId = useId();
  const router = useRouter();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState<Kind>("company");

  const form = useActionForm(createContact, {
    onSuccess: (contact) => {
      setOpen(false);
      toast.success(t("{name} added", { name: contact.name }));
      router.push(`/crm/contacts/${contact.id}`);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant={variant} />}>
        <PlusIcon />
        {t("Add contact")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add contact")}</DialogTitle>
            <DialogDescription>
              {t("A company you sell to, or a person you talk to.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-kind`}>{t("Type")}</FieldLabel>
              <FormSelect
                id={`${fieldId}-kind`}
                name="kind"
                value={kind}
                onValueChange={(value) => {
                  setKind(value === "person" ? "person" : "company");
                }}
                items={[
                  { value: "company", label: t("Company") },
                  { value: "person", label: t("Person") },
                ]}
              />
            </Field>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={200}
                placeholder={
                  kind === "company" ? t("Acme Inc.") : t("Ada Lovelace")
                }
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            {kind === "company" ? (
              <Field>
                <FieldLabel htmlFor={`${fieldId}-domain`}>
                  {t("Domain")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-domain`}
                  name="domain"
                  maxLength={200}
                  placeholder="acme.com"
                />
              </Field>
            ) : (
              <Field>
                <FieldLabel htmlFor={`${fieldId}-email`}>
                  {t("Email")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-email`}
                  name="email"
                  type="email"
                  maxLength={200}
                  placeholder="ada@acme.com"
                />
              </Field>
            )}
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
