"use client";

import { useActionForm } from "better-supabase/react";
import { CopyIcon, PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Alert, AlertDescription } from "@/components/ui/alert";
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

import { createApiKey } from "../api-key-actions";

export function CreateApiKeyDialog() {
  const t = useExtracted("apiKeys");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const form = useActionForm(createApiKey);
  const token = form.data?.token ?? null;
  const error = form.error === undefined ? null : errorMessage(form.error);
  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        // The key is shown once: a reopened dialog starts empty.
        if (!next) form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Create key")}
      </DialogTrigger>
      <DialogContent>
        {token ? (
          <div className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Copy your key")}</DialogTitle>
              <DialogDescription>
                {t(
                  "This is the only time it is shown. Only its hash is stored.",
                )}
              </DialogDescription>
            </DialogHeader>
            <div className="flex gap-2">
              <Input
                value={token}
                readOnly
                className="font-mono"
                aria-label={t("API key")}
              />
              <Button
                variant="outline"
                size="icon"
                aria-label={t("Copy key")}
                onClick={() => {
                  void navigator.clipboard
                    .writeText(token)
                    .then(() => toast.success(t("Key copied")));
                }}
              >
                <CopyIcon />
              </Button>
            </div>
            <Alert>
              <AlertDescription>
                {t(
                  "Your service checks it with apiKeys.verify. Revoke it here when you're done.",
                )}
              </AlertDescription>
            </Alert>
            <DialogFooter>
              <DialogClose render={<Button />}>{t("Done")}</DialogClose>
            </DialogFooter>
          </div>
        ) : (
          <form {...form.formProps} className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Create an API key")}</DialogTitle>
              <DialogDescription>
                {t("Name it after the script or service that uses it.")}
              </DialogDescription>
            </DialogHeader>
            <FieldGroup>
              <Field data-invalid={error ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-api-key-name`}>
                  {t("Name")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-api-key-name`}
                  name="name"
                  required
                  maxLength={80}
                  placeholder="CI"
                />
                {error ? <FieldError>{error}</FieldError> : null}
              </Field>
            </FieldGroup>
            <DialogFooter>
              <DialogClose render={<Button type="button" variant="outline" />}>
                {t("Cancel")}
              </DialogClose>
              <Button type="submit" disabled={form.pending}>
                {t("Create")}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
