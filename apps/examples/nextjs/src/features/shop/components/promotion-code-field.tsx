"use client";

import type { Money } from "better-supabase/commerce";

import { formatMoney, negateMoney } from "better-supabase/commerce";
import { useAction, useActionForm } from "better-supabase/react";
import { TicketPercentIcon, XIcon } from "lucide-react";
import { useExtracted, useLocale } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";

import { Badge } from "@/components/reui/badge";
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
import { useErrorMessage } from "@/lib/use-error-message";

import {
  applyPromotionCode,
  createPromotionCode,
  removePromotionCode,
} from "../shop-actions";

// #region recipe:promotion-code-field
export interface AppliedCode {
  readonly code: string;
  readonly name: string;
  readonly discount: Money;
}

/**
 * Applies a promotion code to a draft order's cart. The block checks the code
 * (active, in its window, under its limits) and the cart's totals come back
 * with the discount, which the list below the field shows.
 */
export function PromotionCodeField({
  cartId,
  applied,
  canCreate,
}: {
  cartId: string;
  applied: readonly AppliedCode[];
  canCreate: boolean;
}) {
  const t = useExtracted("shop");
  const locale = useLocale();
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const form = useActionForm(applyPromotionCode, {
    onSuccess: (code) => {
      toast.success(t("{code} applied", { code }));
    },
  });

  const remove = useAction(removePromotionCode, {
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <div data-recipe="promotion-code-field" className="flex flex-col gap-3">
      <form {...form.formProps}>
        <input type="hidden" name="cartId" value={cartId} />
        <Field data-invalid={error ? true : undefined}>
          <FieldLabel htmlFor={`${fieldId}-code`}>
            {t("Promotion code")}
          </FieldLabel>
          <div className="flex gap-2">
            <Input
              id={`${fieldId}-code`}
              name="code"
              required
              maxLength={32}
              autoComplete="off"
              placeholder="WELCOME10"
              className="font-mono uppercase"
            />
            <Button type="submit" variant="outline" disabled={form.pending}>
              {t("Apply")}
            </Button>
          </div>
          {error ? <FieldError>{error}</FieldError> : null}
        </Field>
      </form>
      {applied.length > 0 ? (
        <ul className="flex flex-col gap-2">
          {applied.map((each) => (
            <li
              key={each.code}
              className="flex items-center justify-between gap-2 text-sm"
            >
              <span className="flex items-center gap-2">
                <Badge variant="success-light" className="font-mono">
                  {each.code}
                </Badge>
                <span className="text-muted-foreground">{each.name}</span>
              </span>
              <span className="flex items-center gap-1">
                <span className="tabular-nums">
                  {formatMoney(negateMoney(each.discount), locale)}
                </span>
                <Button
                  size="icon-sm"
                  variant="ghost"
                  aria-label={t("Remove {code}", { code: each.code })}
                  disabled={remove.pending}
                  onClick={() => {
                    void remove.run({ cartId, code: each.code });
                  }}
                >
                  <XIcon />
                </Button>
              </span>
            </li>
          ))}
        </ul>
      ) : (
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-xs text-muted-foreground">
            {t("No code applied.")}
          </p>
          {canCreate ? <CreatePromotionCodeDialog /> : null}
        </div>
      )}
    </div>
  );
}

/** Creates a percentage promotion with one code, to try the field with. */
export function CreatePromotionCodeDialog() {
  const t = useExtracted("shop");
  const fieldId = useId();
  const errorMessage = useErrorMessage();
  const [open, setOpen] = useState(false);

  const form = useActionForm(createPromotionCode, {
    onSuccess: (code) => {
      toast.success(t("{code} is ready to use", { code }));
      setOpen(false);
    },
  });

  const error = form.error === undefined ? null : errorMessage(form.error);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        form.reset();
      }}
    >
      <DialogTrigger render={<Button size="sm" variant="outline" />}>
        <TicketPercentIcon />
        {t("New promotion code")}
      </DialogTrigger>
      <DialogContent>
        <form {...form.formProps} className="grid gap-6">
          <DialogHeader>
            <DialogTitle>{t("New promotion code")}</DialogTitle>
            <DialogDescription>
              {t("A percentage off the whole order, with one code to enter.")}
            </DialogDescription>
          </DialogHeader>
          <FieldGroup>
            <Field data-invalid={error ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-new-code`}>
                {t("Code")}
              </FieldLabel>
              <Input
                id={`${fieldId}-new-code`}
                name="code"
                required
                maxLength={32}
                autoComplete="off"
                defaultValue="WELCOME10"
                className="font-mono uppercase"
              />
              {error ? <FieldError>{error}</FieldError> : null}
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-percent`}>
                {t("Percent off")}
              </FieldLabel>
              <Input
                id={`${fieldId}-percent`}
                name="percent"
                required
                inputMode="decimal"
                defaultValue="10"
                className="w-24"
              />
              <FieldDescription>
                {t("Above 0 and at most 100, such as 12.5.")}
              </FieldDescription>
            </Field>
          </FieldGroup>
          <DialogFooter>
            <DialogClose render={<Button type="button" variant="outline" />}>
              {t("Cancel")}
            </DialogClose>
            <Button type="submit" disabled={form.pending}>
              {t("Create code")}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
// #endregion recipe:promotion-code-field
