"use client";

import { useAction } from "better-supabase/react";
import { KeySquareIcon, Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { useErrorMessage } from "@/lib/use-error-message";

import type { CredentialRow } from "../builder-queries";

import { createCredential, revokeCredential } from "../builder-actions";

/** The organization's Slack credentials: the token goes to Vault, the row keeps a reference. */
export function CredentialSheet({
  credentials,
}: {
  credentials: readonly CredentialRow[];
}) {
  const t = useExtracted("workflows");
  const id = useId();
  const errorMessage = useErrorMessage();
  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };
  const create = useAction(createCredential, {
    onError,
    onSuccess: () => {
      toast.success(t("Credential saved"));
    },
  });
  const revoke = useAction(revokeCredential, { onError });
  return (
    <Sheet>
      <SheetTrigger render={<Button variant="outline" size="sm" />}>
        <KeySquareIcon />
        {t("Credentials")}
      </SheetTrigger>
      <SheetContent className="gap-6 p-6">
        <SheetHeader className="p-0">
          <SheetTitle>{t("Credentials")}</SheetTitle>
          <SheetDescription>
            {t(
              "Slack bot tokens for the Post to Slack step. The token is stored in Vault and never shown again.",
            )}
          </SheetDescription>
        </SheetHeader>
        <ul className="space-y-2">
          {credentials.map((credential) => (
            <li
              key={credential.id}
              className="flex items-center justify-between gap-2 text-sm"
            >
              <span className="truncate">{credential.name}</span>
              <Button
                variant="ghost"
                size="sm"
                aria-label={t("Revoke")}
                disabled={revoke.pending}
                onClick={() => {
                  void revoke.run({ id: credential.id });
                }}
              >
                <Trash2Icon />
              </Button>
            </li>
          ))}
        </ul>
        <form
          className="space-y-3"
          action={(form) => {
            void create.run({
              name: String(form.get("name") ?? ""),
              secret: String(form.get("secret") ?? ""),
            });
          }}
        >
          <Field>
            <FieldLabel htmlFor={`${id}-name`}>{t("Name")}</FieldLabel>
            <Input id={`${id}-name`} name="name" required maxLength={100} />
          </Field>
          <Field>
            <FieldLabel htmlFor={`${id}-secret`}>{t("Bot token")}</FieldLabel>
            <Input
              id={`${id}-secret`}
              name="secret"
              type="password"
              required
              autoComplete="off"
              placeholder="xoxb-…"
            />
          </Field>
          <Button type="submit" disabled={create.pending}>
            {t("Add credential")}
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
