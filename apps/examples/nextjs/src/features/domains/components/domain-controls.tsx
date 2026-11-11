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
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import {
  addDomain,
  removeDomain,
  setPrimaryDomain,
  verifyDomain,
} from "../domains-actions";

/** The add form. The TXT record to publish shows on each pending row. */
export function AddDomainDialog() {
  const t = useExtracted("domains");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<DbError>();
  const [pending, startTransition] = useTransition();
  const message = error === undefined ? null : errorMessage(error);

  const submit = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const form = new FormData(event.currentTarget);

    startTransition(async () => {
      const added = await addDomain({
        hostname: String(form.get("hostname") ?? ""),
      });

      if (!added.ok) {
        setError(added.error);

        return;
      }

      setError(undefined);
      setOpen(false);
      toast.success(t("Domain added"));
    });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        setError(undefined);
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Add domain")}
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add a domain")}</DialogTitle>
            <DialogDescription>
              {t(
                "Your organization is served on a domain once you publish its TXT record and verify it.",
              )}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={message ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-hostname`}>
                {t("Hostname")}
              </FieldLabel>
              <Input
                id={`${fieldId}-hostname`}
                name="hostname"
                required
                maxLength={253}
                placeholder="app.example.com"
              />
              <FieldDescription>
                {t("A hostname you control, without https://.")}
              </FieldDescription>
              {message ? <FieldError>{message}</FieldError> : null}
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={pending}>
              {t("Add domain")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Verify, make primary and remove, for one hostname. */
export function DomainActions({
  id,
  hostname,
  verified,
  primary,
}: {
  id: string;
  hostname: string;
  verified: boolean;
  primary: boolean;
}) {
  const t = useExtracted("domains");
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
      {verified ? (
        primary ? null : (
          <Button
            variant="outline"
            size="sm"
            disabled={pending}
            onClick={() => {
              run(() => setPrimaryDomain({ id }), t("Primary domain set"));
            }}
          >
            {t("Make primary")}
          </Button>
        )
      ) : (
        <Button
          variant="outline"
          size="sm"
          disabled={pending}
          onClick={() => {
            run(() => verifyDomain({ id }), t("Domain verified"));
          }}
        >
          {t("Verify")}
        </Button>
      )}
      <AlertDialog>
        <AlertDialogTrigger
          render={
            <Button
              variant="ghost"
              size="icon-sm"
              disabled={pending}
              aria-label={t("Remove {hostname}", { hostname })}
            />
          }
        >
          <Trash2Icon />
        </AlertDialogTrigger>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>
              {t("Remove {hostname}?", { hostname })}
            </AlertDialogTitle>
            <AlertDialogDescription>
              {t(
                "The organization stops being served on this domain. You can add it again later.",
              )}
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
            <AlertDialogAction
              variant="destructive"
              disabled={pending}
              onClick={() => {
                run(() => removeDomain({ id }), t("Domain removed"));
              }}
            >
              {t("Remove")}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}

/** The TXT record of a pending hostname, with a copy button for its value. */
export function DomainRecord({ name, value }: { name: string; value: string }) {
  const t = useExtracted("domains");

  return (
    <div className="flex items-center gap-2">
      <code className="max-w-xs truncate text-xs" title={`${name} ${value}`}>
        {name}
      </code>
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label={t("Copy the TXT value")}
        onClick={() => {
          void navigator.clipboard.writeText(value).then(() => {
            toast.success(t("Value copied"));
          });
        }}
      >
        <CopyIcon />
      </Button>
    </div>
  );
}
