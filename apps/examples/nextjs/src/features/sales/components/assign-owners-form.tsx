"use client";

import { useActionForm, useErrorMessage } from "better-supabase/react";
import { UsersIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";

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
import { FormSelect } from "@/features/crm/components/form-select";
import { useRouter } from "@/i18n/navigation";
import { toast } from "@/lib/toast";

import { assignDealOwners } from "../sales-actions";

interface Option {
  readonly value: string;
  readonly label: string;
}

interface DealChoice {
  readonly id: string;
  readonly name: string;
  readonly owner: string | null;
}

/**
 * Picks open deals and one owner, then saves them in one call. The server
 * action accepts up to 100 deals; a refused deal is counted in the message.
 */
export function AssignOwnersForm({
  owners,
  deals,
  unassigned,
}: {
  owners: readonly Option[];
  deals: readonly DealChoice[];
  unassigned: string;
}) {
  const t = useExtracted("sales");
  const router = useRouter();
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);
  const [selected, setSelected] = useState<ReadonlySet<string>>(new Set());

  const form = useActionForm(assignDealOwners, {
    onSuccess: (data) => {
      setOpen(false);
      setSelected(new Set());
      toast.success(
        data.refused === 0
          ? t(
              "{count, plural, one {# deal assigned} other {# deals assigned}}",
              { count: data.assigned },
            )
          : t("{assigned} assigned, {refused} refused", {
              assigned: String(data.assigned),
              refused: String(data.refused),
            }),
      );
      router.refresh();
    },
  });

  const toggle = (id: string, on: boolean) => {
    const next = new Set(selected);

    if (on) {
      next.add(id);
    } else {
      next.delete(id);
    }

    setSelected(next);
  };

  const unowned = deals.filter((deal) => deal.owner === null);
  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        <UsersIcon />
        {t("Assign owner")}
      </DialogTrigger>
      <DialogContent>
        <form
          {...form.formProps}
          className="grid max-h-[calc(100dvh-6rem)] gap-6 overflow-y-auto"
        >
          <DialogHeader>
            <DialogTitle>{t("Assign an owner to deals")}</DialogTitle>
            <DialogDescription>
              {t("Choose the open deals that move to one owner.")}
            </DialogDescription>
          </DialogHeader>
          <input type="hidden" name="dealIds" value={[...selected].join(",")} />
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-owner`}>{t("Owner")}</FieldLabel>
              <FormSelect
                id={`${fieldId}-owner`}
                name="ownerId"
                items={owners}
                defaultValue={owners[0]?.value ?? ""}
              />
              {form.fieldErrors["ownerId"] ? (
                <FieldError>{form.fieldErrors["ownerId"]}</FieldError>
              ) : null}
            </Field>
            <Field>
              <div className="flex items-center justify-between gap-2">
                <FieldLabel>{t("Deals")}</FieldLabel>
                <div className="flex gap-1">
                  <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      setSelected(new Set(unowned.map((deal) => deal.id)));
                    }}
                  >
                    {t("Select unowned")}
                  </Button>
                  <Button
                    type="button"
                    size="sm"
                    variant="ghost"
                    onClick={() => {
                      setSelected(new Set());
                    }}
                  >
                    {t("Clear")}
                  </Button>
                </div>
              </div>
              <ul className="flex max-h-64 flex-col gap-1 overflow-y-auto rounded-lg border p-2">
                {deals.map((deal) => (
                  <li key={deal.id}>
                    <label className="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        className="size-4 accent-primary"
                        checked={selected.has(deal.id)}
                        onChange={(event) => {
                          toggle(deal.id, event.currentTarget.checked);
                        }}
                      />
                      <span className="truncate">{deal.name}</span>
                      <span className="ml-auto text-xs text-muted-foreground">
                        {deal.owner ?? unassigned}
                      </span>
                    </label>
                  </li>
                ))}
              </ul>
              {form.fieldErrors["dealIds"] ? (
                <FieldError>{form.fieldErrors["dealIds"]}</FieldError>
              ) : null}
            </Field>
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button
              type="submit"
              disabled={form.pending || selected.size === 0}
            >
              {t(
                "{count, plural, one {Assign # deal} other {Assign # deals}}",
                { count: selected.size },
              )}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
