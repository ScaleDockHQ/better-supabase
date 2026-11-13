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
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/lib/toast";

import { openIncident } from "../incidents-actions";

/** Opens an incident with a severity and a first timeline entry. */
export function OpenIncidentDialog() {
  const t = useExtracted("incidents");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(openIncident, {
    onSuccess: () => {
      toast.success(t("Incident opened"));
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
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Open incident")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Open incident")}</DialogTitle>
            <DialogDescription>
              {t(
                "Name what broke and how bad it is. Add updates as you learn more.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-title`}>{t("Title")}</FieldLabel>
              <Input
                id={`${fieldId}-title`}
                name="title"
                required
                maxLength={200}
                autoComplete="off"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-severity`}>
                {t("Severity")}
              </FieldLabel>
              <Select
                name="severity"
                defaultValue="sev3"
                items={{
                  sev1: "SEV1",
                  sev2: "SEV2",
                  sev3: "SEV3",
                  sev4: "SEV4",
                }}
              >
                <SelectTrigger id={`${fieldId}-severity`} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="sev1">SEV1</SelectItem>
                  <SelectItem value="sev2">SEV2</SelectItem>
                  <SelectItem value="sev3">SEV3</SelectItem>
                  <SelectItem value="sev4">SEV4</SelectItem>
                </SelectContent>
              </Select>
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-message`}>
                {t("First update")}
              </FieldLabel>
              <Textarea
                id={`${fieldId}-message`}
                name="message"
                maxLength={2000}
                rows={3}
              />
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Open incident")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
