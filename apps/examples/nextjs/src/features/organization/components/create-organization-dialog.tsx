"use client";

import { useExtracted } from "next-intl";
import { useActionState, useId } from "react";
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
} from "@/components/ui/dialog";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { useErrorMessage } from "@/lib/use-error-message";

import { createOrganization } from "../organization-actions";
import { useRefreshSession } from "../use-refresh-session";

export function CreateOrganizationDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const t = useExtracted("organization");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const refreshSession = useRefreshSession();
  const [error, submit, pending] = useActionState(
    async (_previous: string | null, form: FormData) => {
      const result = await createOrganization(form);
      if (!result.ok) return errorMessage(result.error);
      onOpenChange(false);
      await refreshSession("/");
      toast.success(t("Organization created"));
      return null;
    },
    null,
  );
  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <form action={submit} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Create organization")}</DialogTitle>
            <DialogDescription>
              {t(
                "You become its owner. Invite your team from the members page.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-organization-name`}>
                {t("Name")}
              </FieldLabel>
              <Input
                id={`${fieldId}-organization-name`}
                name="name"
                required
                minLength={2}
                maxLength={80}
                autoComplete="organization"
                aria-invalid={error ? true : undefined}
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={pending}>
              {t("Create")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
