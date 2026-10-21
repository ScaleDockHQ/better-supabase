"use client";

import type { DbError } from "better-supabase";
import type { ReactNode } from "react";

import { useAction, useActionForm } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
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
  Field,
  FieldDescription,
  FieldError,
  FieldGroup,
  FieldLabel,
  FieldTitle,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { useErrorMessage } from "@/lib/use-error-message";

import type { SsoDomainRow } from "../sso-queries";

import {
  addSamlConnection,
  addSsoDomain,
  removeSamlConnection,
  removeSsoDomain,
  updateSsoDomain,
  verifySsoDomain,
} from "../sso-actions";

function useSsoErrorMessage(): (error: DbError) => string {
  const t = useExtracted("sso");
  const errorMessage = useErrorMessage();

  return (error) => {
    if (error.hint === "SSO_DOMAIN_RECORD_MISSING") {
      return t(
        "The TXT record was not found yet. DNS changes can take a while to show up.",
      );
    }

    if (error.hint === "SSO_ADMIN_MISSING") {
      return t(
        "The server has no secret key to verify domains or manage SAML.",
      );
    }

    return errorMessage(error);
  };
}

export function AddDomainForm() {
  const t = useExtracted("sso");
  const fieldId = useId();
  const errorMessage = useSsoErrorMessage();

  const form = useActionForm(addSsoDomain, {
    onSuccess: () => {
      toast.success(t("Domain added. Publish its TXT record, then verify it."));
    },
  });

  const error =
    form.error === undefined
      ? null
      : form.error.kind === "validation"
        ? t("Enter a domain such as acme.com.")
        : errorMessage(form.error);

  return (
    <form {...form.formProps} className="flex flex-col gap-2">
      <Field data-invalid={error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-domain`}>
          {t("Email domain")}
        </FieldLabel>
        <div className="flex gap-2">
          <Input
            id={`${fieldId}-domain`}
            name="domain"
            placeholder="acme.com"
            autoComplete="off"
            required
            maxLength={253}
            aria-invalid={error ? true : undefined}
          />
          <Button type="submit" disabled={form.pending}>
            {t("Add domain")}
          </Button>
        </div>
        {error ? <FieldError>{error}</FieldError> : null}
      </Field>
    </form>
  );
}

function ConfirmRemove({
  title,
  description,
  onConfirm,
  pending,
  children,
}: {
  title: string;
  description: string;
  onConfirm: () => Promise<boolean>;
  pending: boolean;
  children: ReactNode;
}) {
  const t = useExtracted("sso");
  const [open, setOpen] = useState(false);

  return (
    <AlertDialog
      open={open}
      onOpenChange={(next) => {
        if (!pending) {
          setOpen(next);
        }
      }}
    >
      <AlertDialogTrigger
        render={<Button type="button" variant="ghost" size="sm" />}
      >
        {children}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel disabled={pending}>
            {t("Cancel")}
          </AlertDialogCancel>
          <AlertDialogAction
            type="button"
            variant="destructive"
            disabled={pending}
            onClick={() => {
              void onConfirm().then((done) => {
                if (done) {
                  setOpen(false);
                }
              });
            }}
          >
            {t("Remove")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

const NO_AUTO_JOIN = "none";

export function DomainActions({ domain }: { domain: SsoDomainRow }) {
  const t = useExtracted("sso");
  const errorMessage = useSsoErrorMessage();

  const onError = (error: DbError) => {
    toast.error(errorMessage(error));
  };

  const verify = useAction(verifySsoDomain, {
    onSuccess: () => {
      toast.success(t("Domain verified"));
    },
    onError,
  });

  const update = useAction(updateSsoDomain, { onError });

  const remove = useAction(removeSsoDomain, {
    onSuccess: () => {
      toast.success(t("Domain removed"));
    },
    onError,
  });

  const roleItems = [
    { value: NO_AUTO_JOIN, label: t("Don't add new users") },
    { value: "member", label: t("Join as member") },
    { value: "admin", label: t("Join as admin") },
  ];

  return (
    <div className="flex flex-wrap items-center gap-2">
      {domain.verified ? (
        <>
          <Select
            value={domain.autoJoinRole ?? NO_AUTO_JOIN}
            items={roleItems}
            disabled={update.pending}
            onValueChange={(value) => {
              void update.run({
                id: domain.id,
                autoJoinRole:
                  value === "member" || value === "admin" ? value : null,
              });
            }}
          >
            <SelectTrigger
              size="sm"
              className="w-44"
              aria-label={t("Role for new users at {domain}", {
                domain: domain.domain,
              })}
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {roleItems.map((item) => (
                <SelectItem key={item.value} value={item.value}>
                  {item.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <div className="flex items-center gap-2">
            <Switch
              id={`enforce-${domain.id}`}
              checked={domain.enforceSso}
              disabled={update.pending}
              onCheckedChange={(checked) => {
                void update.run({ id: domain.id, enforceSso: checked });
              }}
            />
            <Label
              htmlFor={`enforce-${domain.id}`}
              className="text-sm font-normal"
            >
              {t("Require SSO")}
            </Label>
          </div>
        </>
      ) : (
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={verify.pending}
          onClick={() => {
            void verify.run({ id: domain.id });
          }}
        >
          {t("Verify")}
        </Button>
      )}
      <ConfirmRemove
        title={t("Remove {domain}?", { domain: domain.domain })}
        description={t(
          "New users at this domain no longer join automatically, and SAML connections stop covering it.",
        )}
        pending={remove.pending}
        onConfirm={async () => (await remove.run({ id: domain.id })).ok}
      >
        {t("Remove")}
      </ConfirmRemove>
    </div>
  );
}

export function AddSamlForm({
  verifiedDomains,
}: {
  verifiedDomains: readonly string[];
}) {
  const t = useExtracted("sso");
  const fieldId = useId();
  const errorMessage = useSsoErrorMessage();
  const [excluded, setExcluded] = useState<readonly string[]>([]);

  const domains = verifiedDomains.filter(
    (domain) => !excluded.includes(domain),
  );

  const [metadataUrl, setMetadataUrl] = useState("");

  const add = useAction(addSamlConnection, {
    onSuccess: () => {
      setMetadataUrl("");
      toast.success(t("SAML connection added"));
    },
  });

  const error =
    add.error === undefined
      ? null
      : add.error.kind === "validation"
        ? t(
            "Enter the https URL of your identity provider's metadata and pick a domain.",
          )
        : errorMessage(add.error);

  return (
    <form
      className="flex flex-col gap-4"
      onSubmit={(event) => {
        event.preventDefault();
        void add.run({ metadataUrl, domains });
      }}
    >
      <FieldGroup>
        <Field data-invalid={error ? true : undefined}>
          <FieldLabel htmlFor={`${fieldId}-metadata`}>
            {t("Metadata URL")}
          </FieldLabel>
          <Input
            id={`${fieldId}-metadata`}
            type="url"
            value={metadataUrl}
            onChange={(event) => {
              setMetadataUrl(event.target.value);
            }}
            placeholder="https://idp.example.com/saml/metadata"
            required
            aria-invalid={error ? true : undefined}
          />
          <FieldDescription>
            {t(
              "Your identity provider shows this URL in its SAML app settings.",
            )}
          </FieldDescription>
        </Field>
        <Field>
          <FieldTitle>{t("Domains")}</FieldTitle>
          <div className="flex flex-wrap gap-4">
            {verifiedDomains.map((domain) => (
              <div key={domain} className="flex items-center gap-2">
                <Checkbox
                  id={`${fieldId}-${domain}`}
                  checked={domains.includes(domain)}
                  onCheckedChange={(checked) => {
                    setExcluded((current) =>
                      checked
                        ? current.filter((item) => item !== domain)
                        : [...current, domain],
                    );
                  }}
                />
                <Label
                  htmlFor={`${fieldId}-${domain}`}
                  className="text-sm font-normal"
                >
                  {domain}
                </Label>
              </div>
            ))}
          </div>
          {error ? <FieldError>{error}</FieldError> : null}
        </Field>
      </FieldGroup>
      <div>
        <Button type="submit" disabled={add.pending || domains.length === 0}>
          {t("Add connection")}
        </Button>
      </div>
    </form>
  );
}

export function RemoveConnectionButton({ id }: { id: string }) {
  const t = useExtracted("sso");
  const errorMessage = useSsoErrorMessage();

  const remove = useAction(removeSamlConnection, {
    onSuccess: () => {
      toast.success(t("SAML connection removed"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <ConfirmRemove
      title={t("Remove this SAML connection?")}
      description={t(
        "Members who sign in with it have to use another sign-in method.",
      )}
      pending={remove.pending}
      onConfirm={async () => (await remove.run({ id })).ok}
    >
      {t("Remove")}
    </ConfirmRemove>
  );
}
