"use client";

import { useAction } from "better-supabase/react";
import { CopyIcon, Link2Icon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
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
  Card,
  CardAction,
  CardContent,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
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
  Empty,
  EmptyContent,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { revokeCustomerShareLinks } from "@/lib/supabase/features/customer/customer-actions";
import { useErrorMessage } from "@/lib/use-error-message";

import type { Loaded, ShareLinkRow } from "../customer-record-queries";

import { createShareLink } from "../customer-record-actions";
import { RecordCardSkeleton, RecordLoadError } from "./record-card-states";

// #region recipe:share-link-dialog

type ExpiryDays = 1 | 7 | 30 | 0;

const isExpiry = (value: unknown): value is ExpiryDays =>
  value === 1 || value === 7 || value === 30 || value === 0;

type LinkState = "active" | "expired" | "revoked";

const LINK_VARIANT = {
  active: "success-light",
  expired: "warning-light",
  revoked: "secondary",
} as const satisfies Record<LinkState, string>;

function stateOf(link: ShareLinkRow): LinkState {
  if (link.revokedAt !== null) {
    return "revoked";
  }

  return link.expired ? "expired" : "active";
}

/** View links to the customer: create one, see who can still open them, revoke. */
export function ShareLinkDialog({
  customerId,
  links,
  canCreate,
}: {
  customerId: string;
  links: Loaded<readonly ShareLinkRow[]>;
  canCreate: boolean;
}) {
  const t = useExtracted("customers");

  return (
    <Card size="sm" data-recipe="share-link-dialog">
      <CardHeader>
        <CardTitle>{t("Share links")}</CardTitle>
        {canCreate && links.kind === "ok" && links.data.length > 0 ? (
          <CardAction>
            <CreateShareLink customerId={customerId} />
          </CardAction>
        ) : null}
      </CardHeader>
      <CardContent>
        {links.kind === "error" ? (
          <RecordLoadError title={t("The share links didn't load")} />
        ) : links.data.length === 0 ? (
          <Empty className="border">
            <EmptyHeader>
              <EmptyMedia variant="icon">
                <Link2Icon />
              </EmptyMedia>
              <EmptyTitle>{t("No share links")}</EmptyTitle>
              <EmptyDescription>
                {t("A link lets someone outside the team view this customer.")}
              </EmptyDescription>
            </EmptyHeader>
            {canCreate ? (
              <EmptyContent>
                <CreateShareLink customerId={customerId} />
              </EmptyContent>
            ) : null}
          </Empty>
        ) : (
          <ShareLinkList
            customerId={customerId}
            links={links.data}
            canRevoke={canCreate}
          />
        )}
      </CardContent>
    </Card>
  );
}

function ShareLinkList({
  customerId,
  links,
  canRevoke,
}: {
  customerId: string;
  links: readonly ShareLinkRow[];
  canRevoke: boolean;
}) {
  const t = useExtracted("customers");
  const format = useFormatter();

  const label: Record<LinkState, string> = {
    active: t("Active"),
    expired: t("Expired"),
    revoked: t("Revoked"),
  };

  return (
    <ul className="flex flex-col divide-y" data-testid="share-links">
      {links.map((link) => {
        const state = stateOf(link);

        return (
          <li
            key={link.id}
            className="flex items-center justify-between gap-2 py-2"
          >
            <div className="flex min-w-0 flex-col gap-1">
              <div className="flex items-center gap-2">
                <Badge variant={LINK_VARIANT[state]}>{label[state]}</Badge>
                <span className="text-sm">{t("View only")}</span>
              </div>
              <span className="text-xs text-muted-foreground">
                {link.expiresAt === null
                  ? t("Never expires")
                  : t("Expires {date}", {
                      date: format.dateTime(link.expiresAt, {
                        dateStyle: "medium",
                        timeStyle: "short",
                      }),
                    })}
              </span>
            </div>
            {canRevoke && state === "active" ? (
              <RevokeShareLink id={link.id} customerId={customerId} />
            ) : null}
          </li>
        );
      })}
    </ul>
  );
}

function CreateShareLink({ customerId }: { customerId: string }) {
  const t = useExtracted("customers");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [expiresInDays, setExpiresInDays] = useState<ExpiryDays>(7);
  const [url, setUrl] = useState<string | null>(null);

  const create = useAction(createShareLink, {
    onSuccess: ({ token }) => {
      setUrl(`${window.location.origin}/share/${token}`);
    },
  });

  const expiries = [
    { value: 1, label: t("1 day") },
    { value: 7, label: t("7 days") },
    { value: 30, label: t("30 days") },
    { value: 0, label: t("Never") },
  ];

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);

        if (!next) {
          setUrl(null);
          create.reset();
        }
      }}
    >
      <DialogTrigger render={<Button size="sm" />}>
        <Link2Icon />
        {t("Create link")}
      </DialogTrigger>
      <DialogContent>
        {url ? (
          <div className="grid gap-6">
            <DialogHeader>
              <DialogTitle>{t("Link created")}</DialogTitle>
              <DialogDescription>
                {t(
                  "Copy it now. It is shown once; revoke it here to close it.",
                )}
              </DialogDescription>
            </DialogHeader>
            <div className="flex gap-2">
              <Input
                value={url}
                readOnly
                aria-label={t("Share link")}
                data-testid="share-link-url"
              />
              <Button
                variant="outline"
                size="icon"
                aria-label={t("Copy link")}
                onClick={() => {
                  void navigator.clipboard
                    .writeText(url)
                    .then(() => toast.success(t("Link copied")));
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
          <form
            className="grid gap-6"
            onSubmit={(event) => {
              event.preventDefault();
              void create.run({ customerId, expiresInDays });
            }}
          >
            <DialogHeader>
              <DialogTitle>{t("Share this customer")}</DialogTitle>
              <DialogDescription>
                {t(
                  "Anyone with the link can view the customer until it expires.",
                )}
              </DialogDescription>
            </DialogHeader>
            <Field data-invalid={create.error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-expiry`}>
                {t("Expires after")}
              </FieldLabel>
              <Select
                value={expiresInDays}
                items={expiries}
                onValueChange={(value) => {
                  if (isExpiry(value)) {
                    setExpiresInDays(value);
                  }
                }}
              >
                <SelectTrigger id={`${fieldId}-expiry`} className="w-40">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {expiries.map((each) => (
                    <SelectItem key={each.value} value={each.value}>
                      {each.label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
              {create.error ? (
                <FieldError>{errorMessage(create.error)}</FieldError>
              ) : null}
            </Field>
            <DialogFooter>
              <DialogClose render={<Button type="button" variant="outline" />}>
                {t("Cancel")}
              </DialogClose>
              <Button type="submit" disabled={create.pending}>
                {t("Create link")}
              </Button>
            </DialogFooter>
          </form>
        )}
      </DialogContent>
    </Dialog>
  );
}

function RevokeShareLink({
  id,
  customerId,
}: {
  id: string;
  customerId: string;
}) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();

  const revoke = useAction(revokeCustomerShareLinks, {
    onSuccess: () => {
      toast.success(t("Link revoked"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <AlertDialog>
      <AlertDialogTrigger
        render={
          <Button size="sm" variant="outline" disabled={revoke.pending} />
        }
      >
        {t("Revoke")}
      </AlertDialogTrigger>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{t("Revoke this link?")}</AlertDialogTitle>
          <AlertDialogDescription>
            {t("Anyone who has it can no longer open the customer.")}
          </AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>{t("Cancel")}</AlertDialogCancel>
          <AlertDialogAction
            variant="destructive"
            onClick={() => {
              void revoke.run({ id: customerId, input: { id } });
            }}
          >
            {t("Revoke")}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

/** The share links card while its rows load. */
export function ShareLinkDialogSkeleton() {
  return <RecordCardSkeleton rows={2} />;
}

// #endregion recipe:share-link-dialog
