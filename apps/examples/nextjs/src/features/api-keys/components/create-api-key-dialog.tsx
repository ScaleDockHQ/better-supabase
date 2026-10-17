"use client";

import type { DbError } from "better-supabase";

import { CopyIcon, PlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { type SubmitEvent, useId, useState } from "react";
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

/** The create form, then the new token, which is shown only this once. */
export function CreateApiKeyDialog({
  token,
  creating,
  error,
  onCreate,
  onClose,
}: {
  token: string | undefined;
  creating: boolean;
  error: DbError | undefined;
  onCreate: (name: string) => Promise<void>;
  onClose: () => void;
}) {
  const t = useExtracted("apiKeys");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const message = error === undefined ? null : errorMessage(error);

  const submit = async (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (name.trim()) {
      await onCreate(name.trim());
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setName("");
        // The key is shown once: a reopened dialog starts empty.
        if (!next) {
          onClose();
        }
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
          <form onSubmit={(event) => void submit(event)} className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Create an API key")}</DialogTitle>
              <DialogDescription>
                {t("Name it after the script or service that uses it.")}
              </DialogDescription>
            </DialogHeader>
            <FieldGroup>
              <Field data-invalid={message ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-api-key-name`}>
                  {t("Name")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-api-key-name`}
                  name="name"
                  value={name}
                  onChange={(event) => {
                    setName(event.target.value);
                  }}
                  required
                  maxLength={80}
                  placeholder="CI"
                />
                {message ? <FieldError>{message}</FieldError> : null}
              </Field>
            </FieldGroup>
            <DialogFooter>
              <DialogClose render={<Button type="button" variant="outline" />}>
                {t("Cancel")}
              </DialogClose>
              <Button type="submit" disabled={creating}>
                {t("Create")}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}
