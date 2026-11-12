"use client";

import type { DbError } from "better-supabase";
import type { SubmitEvent } from "react";

import { CopyIcon, PlusIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState, useTransition } from "react";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from "@/components/ui/alert-dialog";
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
import { Switch } from "@/components/ui/switch";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { CreatedIncomingWebhook } from "../incoming-webhooks-actions";

import {
  createIncomingWebhook,
  deleteIncomingWebhook,
  setIncomingWebhookEnabled,
} from "../incoming-webhooks-actions";

type Verify = "none" | "standard-webhooks" | "hmac-sha256" | "shared-secret";

function CopyField({ label, value }: { label: string; value: string }) {
  const t = useExtracted("incomingWebhooks");

  return (
    <div className="flex gap-2">
      <Input value={value} readOnly className="font-mono" aria-label={label} />
      <Button
        variant="outline"
        size="icon"
        aria-label={t("Copy {label}", { label })}
        onClick={() => {
          void navigator.clipboard.writeText(value).then(() => {
            toast.success(t("Copied"));
          });
        }}
      >
        <CopyIcon />
      </Button>
    </div>
  );
}

/** The create form, then the trigger URL and signing secret, shown only once. */
export function CreateIncomingWebhookDialog() {
  const t = useExtracted("incomingWebhooks");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [verify, setVerify] = useState<Verify>("standard-webhooks");
  const [created, setCreated] = useState<CreatedIncomingWebhook>();
  const [error, setError] = useState<DbError>();
  const [pending, startTransition] = useTransition();
  const message = error === undefined ? null : errorMessage(error);

  const submit = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);

    startTransition(async () => {
      const result = await createIncomingWebhook({
        name: String(form.get("name") ?? ""),
        verify,
      });

      if (!result.ok) {
        setError(result.error);

        return;
      }

      setError(undefined);
      setCreated(result.data);
    });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        // The token is shown once: a reopened dialog starts empty.
        if (!next) {
          setCreated(undefined);
          setError(undefined);
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Add endpoint")}
      </DialogTrigger>
      <DialogContent>
        {created ? (
          <div className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Copy the trigger URL")}</DialogTitle>
              <DialogDescription>
                {t(
                  "This is the only time the token and the secret are shown. Senders post to the URL.",
                )}
              </DialogDescription>
            </DialogHeader>
            <CopyField
              label={t("Trigger path")}
              value={`/api/hooks/${created.token}`}
            />
            {created.secret ? (
              <CopyField label={t("Secret")} value={created.secret} />
            ) : null}
            <DialogFooter>
              <DialogClose render={<Button />}>{t("Done")}</DialogClose>
            </DialogFooter>
          </div>
        ) : (
          <form onSubmit={submit} className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Add an incoming endpoint")}</DialogTitle>
              <DialogDescription>
                {t(
                  "Deliveries land in the webhook inbox for a worker to process.",
                )}
              </DialogDescription>
            </DialogHeader>
            <FieldGroup>
              <Field data-invalid={message ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
                <Input
                  id={`${fieldId}-name`}
                  name="name"
                  required
                  maxLength={100}
                  placeholder="Payment provider"
                />
                {message ? <FieldError>{message}</FieldError> : null}
              </Field>
              <Field>
                <FieldLabel>{t("Verification")}</FieldLabel>
                <Select
                  value={verify}
                  onValueChange={(next) => {
                    if (
                      next === "none" ||
                      next === "standard-webhooks" ||
                      next === "hmac-sha256" ||
                      next === "shared-secret"
                    ) {
                      setVerify(next);
                    }
                  }}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    <SelectItem value="standard-webhooks">
                      {t("Standard Webhooks signature")}
                    </SelectItem>
                    <SelectItem value="hmac-sha256">
                      {t("HMAC SHA-256 header")}
                    </SelectItem>
                    <SelectItem value="shared-secret">
                      {t("Shared secret header")}
                    </SelectItem>
                    <SelectItem value="none">{t("None")}</SelectItem>
                  </SelectContent>
                </Select>
              </Field>
            </FieldGroup>
            <DialogFooter>
              <DialogClose render={<Button type="button" variant="outline" />}>
                {t("Cancel")}
              </DialogClose>
              <Button type="submit" disabled={pending}>
                {t("Add endpoint")}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}

/** The enable switch and delete, for one endpoint. */
export function IncomingWebhookActions({
  id,
  name,
  enabled,
}: {
  id: string;
  name: string;
  enabled: boolean;
}) {
  const t = useExtracted("incomingWebhooks");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  const run = (
    action: () => Promise<{ ok: true } | { ok: false; error: DbError }>,
    success: string,
  ) => {
    startTransition(async () => {
      const result = await action();

      if (result.ok) {
        toast.success(success);
      } else {
        toast.error(errorMessage(result.error));
      }
    });
  };

  return (
    <div className="flex items-center justify-end gap-2">
      <Switch
        checked={enabled}
        disabled={pending}
        aria-label={t("Enable {name}", { name })}
        onCheckedChange={(next) => {
          run(
            () => setIncomingWebhookEnabled({ id, enabled: next }),
            next ? t("Endpoint turned on") : t("Endpoint turned off"),
          );
        }}
      />
      <AlertDialog>
        <AlertDialogTrigger
          render={
            <Button
              variant="ghost"
              size="icon-sm"
              disabled={pending}
              aria-label={t("Delete {name}", { name })}
            />
          }
        >
          <Trash2Icon />
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>{t("Delete {name}?", { name })}</AlertDialogTitle>
            <AlertDialogDescription>
              {t(
                "Its secrets are deleted too. Senders that post to its URL get a 404.",
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              disabled={pending}
              onClick={() => {
                run(() => deleteIncomingWebhook({ id }), t("Endpoint deleted"));
              }}
            >
              {t("Delete")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
