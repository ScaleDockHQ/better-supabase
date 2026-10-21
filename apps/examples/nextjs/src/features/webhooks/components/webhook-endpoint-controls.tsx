"use client";

import type { DbError } from "better-supabase";
import type { SubmitEvent } from "react";

import { CopyIcon, PlusIcon, SendIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState, useTransition } from "react";
import { toast } from "sonner";

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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  createWebhookEndpoint,
  deleteWebhookEndpoint,
  redeliverWebhook,
  sendTestWebhook,
  setWebhookEndpointEnabled,
} from "../webhooks-actions";

/** The create form, then the endpoint's signing secret, shown only this once. */
export function CreateWebhookDialog() {
  const t = useExtracted("webhooks");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [secret, setSecret] = useState<string>();
  const [error, setError] = useState<DbError>();
  const [pending, startTransition] = useTransition();
  const message = error === undefined ? null : errorMessage(error);

  const submit = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);

    startTransition(async () => {
      const created = await createWebhookEndpoint({
        name: String(form.get("name") ?? ""),
        url: String(form.get("url") ?? ""),
        eventTypes: String(form.get("eventTypes") ?? ""),
      });

      if (!created.ok) {
        setError(created.error);

        return;
      }

      setError(undefined);
      setSecret(created.data.secret);
    });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        // The secret is shown once: a reopened dialog starts empty.
        if (!next) {
          setSecret(undefined);
          setError(undefined);
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Add endpoint")}
      </DialogTrigger>
      <DialogContent>
        {secret ? (
          <div className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Copy the signing secret")}</DialogTitle>
              <DialogDescription>
                {t(
                  "This is the only time it is shown. Your receiver checks each delivery's signature with it.",
                )}
              </DialogDescription>
            </DialogHeader>
            <div className="flex gap-2">
              <Input
                value={secret}
                readOnly
                className="font-mono"
                aria-label={t("Signing secret")}
              />
              <Button
                variant="outline"
                size="icon"
                aria-label={t("Copy secret")}
                onClick={() => {
                  void navigator.clipboard
                    .writeText(secret)
                    .then(() => toast.success(t("Secret copied")));
                }}
              >
                <CopyIcon />
              </Button>
            </div>
            <DialogFooter>
              <DialogClose render={<Button />}>{t("Done")}</DialogClose>
            </DialogFooter>
          </div>
        ) : (
          <form onSubmit={submit} className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Add a webhook endpoint")}</DialogTitle>
              <DialogDescription>
                {t("Events that match the filter are sent to this URL.")}
              </DialogDescription>
            </DialogHeader>
            <FieldGroup>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-name`}>{t("Name")}</FieldLabel>
                <Input
                  id={`${fieldId}-name`}
                  name="name"
                  required
                  maxLength={100}
                  placeholder="Billing service"
                />
              </Field>
              <Field>
                <FieldLabel htmlFor={`${fieldId}-url`}>{t("URL")}</FieldLabel>
                <Input
                  id={`${fieldId}-url`}
                  name="url"
                  type="url"
                  required
                  pattern="https://.*"
                  placeholder="https://example.com/webhooks"
                />
                <FieldDescription>{t("It must use HTTPS.")}</FieldDescription>
              </Field>
              <Field data-invalid={message ? true : undefined}>
                <FieldLabel htmlFor={`${fieldId}-events`}>
                  {t("Events")}
                </FieldLabel>
                <Input
                  id={`${fieldId}-events`}
                  name="eventTypes"
                  required
                  defaultValue="*"
                  className="font-mono"
                />
                <FieldDescription>
                  {t(
                    "Comma-separated event types. Use * for every event, or invoice.* for a group.",
                  )}
                </FieldDescription>
                {message ? <FieldError>{message}</FieldError> : null}
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

/** The enable switch, a test event and delete, for one endpoint. */
export function WebhookEndpointActions({
  id,
  name,
  enabled,
}: {
  id: string;
  name: string;
  enabled: boolean;
}) {
  const t = useExtracted("webhooks");
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
            () => setWebhookEndpointEnabled({ id, enabled: next }),
            next ? t("Endpoint turned on") : t("Endpoint turned off"),
          );
        }}
      />
      <Button
        variant="ghost"
        size="icon-sm"
        disabled={pending || !enabled}
        aria-label={t("Send a test event to {name}", { name })}
        onClick={() => {
          run(() => sendTestWebhook({ id }), t("Test event queued"));
        }}
      >
        <SendIcon />
      </Button>
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
                "Its deliveries and signing secrets are deleted too. Events stop going to this URL.",
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              disabled={pending}
              onClick={() => {
                run(() => deleteWebhookEndpoint({ id }), t("Endpoint deleted"));
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

/** Queues a finished delivery again. */
export function RedeliverButton({ id }: { id: string }) {
  const t = useExtracted("webhooks");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      variant="outline"
      size="sm"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const queued = await redeliverWebhook({ id });

          if (queued.ok) {
            toast.success(t("Delivery queued again"));
          } else {
            toast.error(errorMessage(queued.error));
          }
        });
      }}
    >
      {t("Retry")}
    </Button>
  );
}

/** The deliveries empty state's action: a test event to the first endpoint. */
export function SendTestEventButton({ id }: { id: string }) {
  const t = useExtracted("webhooks");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const sent = await sendTestWebhook({ id });

          if (sent.ok) {
            toast.success(t("Test event queued"));
          } else {
            toast.error(errorMessage(sent.error));
          }
        });
      }}
    >
      <SendIcon />
      {t("Send a test event")}
    </Button>
  );
}
