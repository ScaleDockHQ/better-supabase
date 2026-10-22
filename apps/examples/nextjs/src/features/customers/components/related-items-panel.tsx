"use client";

import { useAction } from "better-supabase/react";
import { LinkIcon, UnlinkIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import { Field, FieldError, FieldLabel } from "@/components/ui/field";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { SubjectLink } from "@/features/subjects/components/subject-link";
import {
  linkCustomerRelations,
  unlinkCustomerRelations,
} from "@/lib/supabase/features/customer/customer-actions";
import { useErrorMessage } from "@/lib/use-error-message";

import type {
  Loaded,
  RelatedCustomer,
  Relations,
} from "../customer-record-queries";

import { RecordCardSkeleton, RecordLoadError } from "./record-card-states";

// #region recipe:related-items-panel

/** Customers linked to this one (the `relates` kind), and a picker to link more. */
export function RelatedItemsPanel({
  customerId,
  relations,
  canManage,
}: {
  customerId: string;
  relations: Loaded<Relations>;
  canManage: boolean;
}) {
  const t = useExtracted("customers");

  return (
    <Card size="sm" data-recipe="related-items-panel">
      <CardHeader>
        <CardTitle>{t("Related customers")}</CardTitle>
        <CardDescription>
          {t("Link customers that belong together, such as a parent company.")}
        </CardDescription>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        {relations.kind === "error" ? (
          <RecordLoadError title={t("The related customers didn't load")} />
        ) : (
          <>
            {relations.data.links.length === 0 ? (
              <Empty className="border">
                <EmptyHeader>
                  <EmptyMedia variant="icon">
                    <LinkIcon />
                  </EmptyMedia>
                  <EmptyTitle>{t("No related customers")}</EmptyTitle>
                  <EmptyDescription>
                    {canManage
                      ? t("Pick a customer below to link it.")
                      : t("Nobody linked a customer yet.")}
                  </EmptyDescription>
                </EmptyHeader>
              </Empty>
            ) : (
              <RelatedList
                customerId={customerId}
                links={relations.data.links}
                canManage={canManage}
              />
            )}
            {canManage ? (
              <LinkForm
                customerId={customerId}
                options={relations.data.options.filter(
                  (option) =>
                    !relations.data.links.some(
                      (link) =>
                        link.subjectType === "customer" &&
                        link.subjectId === option.id,
                    ),
                )}
              />
            ) : null}
          </>
        )}
      </CardContent>
    </Card>
  );
}

function RelatedList({
  customerId,
  links,
  canManage,
}: {
  customerId: string;
  links: readonly RelatedCustomer[];
  canManage: boolean;
}) {
  const t = useExtracted("customers");
  const errorMessage = useErrorMessage();

  const unlink = useAction(unlinkCustomerRelations, {
    onSuccess: () => {
      toast.success(t("Link removed"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <ul className="flex flex-col divide-y" data-testid="related-customers">
      {links.map((link) => (
        <li
          key={link.id}
          className="flex items-center justify-between gap-2 py-2"
        >
          <div className="flex min-w-0 items-center gap-2">
            <SubjectLink
              subject={{ type: link.subjectType, id: link.subjectId }}
            />
            {link.kind === "relates" ? null : (
              <Badge variant="outline">{link.kind}</Badge>
            )}
          </div>
          {canManage ? (
            <Button
              size="icon-sm"
              variant="ghost"
              aria-label={t("Remove link")}
              disabled={unlink.pendingInputs.some(
                (input) =>
                  !(input instanceof FormData) &&
                  input.input.target.id === link.subjectId,
              )}
              onClick={() => {
                void unlink.run({
                  id: customerId,
                  input: {
                    kind: link.kind,
                    target: { type: link.subjectType, id: link.subjectId },
                  },
                });
              }}
            >
              <UnlinkIcon />
            </Button>
          ) : null}
        </li>
      ))}
    </ul>
  );
}

function LinkForm({
  customerId,
  options,
}: {
  customerId: string;
  options: readonly { readonly id: string; readonly name: string }[];
}) {
  const t = useExtracted("customers");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [targetId, setTargetId] = useState<string | null>(null);

  const link = useAction(linkCustomerRelations, {
    onSuccess: () => {
      setTargetId(null);
      toast.success(t("Customer linked"));
    },
  });

  const items = options.map((option) => ({
    value: option.id,
    label: option.name,
  }));

  if (items.length === 0) {
    return null;
  }

  return (
    <form
      className="flex items-end gap-2"
      onSubmit={(event) => {
        event.preventDefault();

        if (targetId) {
          void link.run({
            id: customerId,
            input: {
              kind: "relates",
              target: { type: "customer", id: targetId },
            },
          });
        }
      }}
    >
      <Field data-invalid={link.error ? true : undefined}>
        <FieldLabel htmlFor={`${fieldId}-related`}>
          {t("Link a customer")}
        </FieldLabel>
        <Select
          value={targetId}
          items={items}
          onValueChange={(value) => {
            setTargetId(value);
          }}
        >
          <SelectTrigger id={`${fieldId}-related`} className="w-full">
            <SelectValue placeholder={t("Pick a customer")} />
          </SelectTrigger>
          <SelectContent>
            {items.map((item) => (
              <SelectItem key={item.value} value={item.value}>
                {item.label}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {link.error ? (
          <FieldError>{errorMessage(link.error)}</FieldError>
        ) : null}
      </Field>
      <Button
        type="submit"
        variant="outline"
        disabled={!targetId || link.pending}
      >
        {t("Link")}
      </Button>
    </form>
  );
}

/** The related customers card while its rows load. */
export function RelatedItemsPanelSkeleton() {
  return <RecordCardSkeleton rows={2} />;
}

// #endregion recipe:related-items-panel
