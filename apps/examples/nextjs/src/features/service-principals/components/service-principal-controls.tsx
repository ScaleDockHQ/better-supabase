"use client";

import type { DbError } from "better-supabase";
import type { SubmitEvent } from "react";

import { PlusIcon } from "lucide-react";
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
import { Checkbox } from "@/components/ui/checkbox";
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

import {
  createServicePrincipal,
  disableServicePrincipal,
} from "../service-principals-actions";

type PrincipalRole = "member" | "admin";

/** Names a new service principal, picks its role, and can make it the default. */
export function CreateServicePrincipalDialog() {
  const t = useExtracted("servicePrincipals");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [role, setRole] = useState<PrincipalRole>("member");
  const [isDefault, setIsDefault] = useState(false);
  const [error, setError] = useState<DbError>();
  const [pending, startTransition] = useTransition();
  const message = error === undefined ? null : errorMessage(error);

  const roles: Record<PrincipalRole, string> = {
    member: t("Member"),
    admin: t("Admin"),
  };

  const submit = (event: SubmitEvent<HTMLFormElement>) => {
    event.preventDefault();
    const name = String(new FormData(event.currentTarget).get("name") ?? "");

    startTransition(async () => {
      const created = await createServicePrincipal({ name, role, isDefault });

      if (!created.ok) {
        setError(created.error);

        return;
      }

      toast.success(t("Service principal added"));
      setOpen(false);
    });
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          setRole("member");
          setIsDefault(false);
          setError(undefined);
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <PlusIcon />
        {t("Add principal")}
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={submit} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("Add a service principal")}</DialogTitle>
            <DialogDescription>
              {t(
                "A machine identity that can't sign in. Workflows and webhooks run as it, with its role's permissions.",
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
                maxLength={80}
                placeholder="Nightly sync"
              />
              {message ? <FieldError>{message}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-role`}>{t("Role")}</FieldLabel>
              <Select
                value={role}
                items={roles}
                onValueChange={(next) => {
                  if (next === "member" || next === "admin") {
                    setRole(next);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-role`} className="w-full">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="member">{roles.member}</SelectItem>
                  <SelectItem value="admin">{roles.admin}</SelectItem>
                </SelectContent>
              </Select>
            </Field>
            <Field orientation="horizontal">
              <Checkbox
                id={`${fieldId}-default`}
                checked={isDefault}
                onCheckedChange={(checked) => {
                  setIsDefault(checked);
                }}
              />
              <div className="flex flex-col gap-1">
                <FieldLabel htmlFor={`${fieldId}-default`}>
                  {t("Make it the default")}
                </FieldLabel>
                <FieldDescription>
                  {t("Work the organization owns runs as the default.")}
                </FieldDescription>
              </div>
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={pending}>
              {t("Add principal")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}

/** Disables one principal behind a confirm. */
export function DisableServicePrincipalButton({
  id,
  name,
}: {
  id: string;
  name: string;
}) {
  const t = useExtracted("servicePrincipals");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={<Button variant="outline" size="sm" disabled={pending} />}
      >
        {t("Disable")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("Disable {name}?", { name })}</AlertDialogTitle>
          <AlertDialogDescription>
            {t(
              "It loses its membership, so workflows and webhooks that run as it stop. This can't be undone.",
            )}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            disabled={pending}
            onClick={() => {
              startTransition(async () => {
                const disabled = await disableServicePrincipal({ id });

                if (disabled.ok) {
                  toast.success(t("Service principal disabled"));
                } else {
                  toast.error(errorMessage(disabled.error));
                }
              });
            }}
          >
            {t("Disable")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
