"use client";

import { useActionForm } from "better-supabase/react";
import { CircleCheckIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";
import { useId, useState } from "react";

import { Badge } from "@/components/reui/badge";
import { Button } from "@/components/ui/button";
import {
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyMedia,
  EmptyTitle,
} from "@/components/ui/empty";
import {
  Field,
  FieldError,
  FieldGroup,
  FieldLabel,
} from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { useErrorMessage } from "@/lib/use-error-message";

import type { PublicBookingDay, PublicSlot } from "../bookings-queries";

import { bookSlot } from "../bookings-actions";

export function SlotPicker({
  token,
  days,
}: {
  token: string;
  days: readonly (PublicBookingDay & { readonly label: string })[];
}) {
  const t = useExtracted("bookings");
  const format = useFormatter();
  const fieldId = useId();
  const errorMessage = useErrorMessage();

  const [picked, setPicked] = useState<(PublicSlot & { day: string }) | null>(
    null,
  );

  const form = useActionForm(bookSlot);
  const error = form.error === undefined ? null : errorMessage(form.error);

  if (form.data) {
    return (
      <Empty className="border">
        <EmptyHeader>
          <EmptyMedia variant="icon">
            <CircleCheckIcon />
          </EmptyMedia>
          <EmptyTitle>{t("You're booked")}</EmptyTitle>
          <EmptyDescription>
            {format.dateTime(new Date(form.data.startsAt), {
              dateStyle: "full",
              timeStyle: "short",
            })}
          </EmptyDescription>
        </EmptyHeader>
        <Badge variant="success-light">{t("Confirmed")}</Badge>
      </Empty>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-4">
        {days.map((day) => (
          <section
            key={day.date}
            aria-label={day.label}
            className="flex flex-col gap-2"
          >
            <h3 className="text-sm font-medium">{day.label}</h3>
            <div className="flex flex-wrap gap-2">
              {day.slots.map((slot) => {
                const selected =
                  picked?.startsAt === slot.startsAt &&
                  picked.resourceId === slot.resourceId;

                return (
                  <Button
                    key={`${slot.resourceId}:${slot.startsAt}`}
                    type="button"
                    size="sm"
                    variant={selected ? "default" : "outline"}
                    aria-pressed={selected}
                    className="tabular-nums"
                    onClick={() => {
                      setPicked({ ...slot, day: day.label });
                    }}
                  >
                    {slot.time}
                  </Button>
                );
              })}
            </div>
          </section>
        ))}
      </div>
      {picked ? (
        <form {...form.formProps} className="flex flex-col gap-4 border-t pt-4">
          <input type="hidden" name="token" value={token} />
          <input type="hidden" name="resourceId" value={picked.resourceId} />
          <input type="hidden" name="startsAt" value={picked.startsAt} />
          <p className="text-sm">
            {t("{day} at {time}", { day: picked.day, time: picked.time })}
          </p>
          <FieldGroup>
            <Field data-invalid={form.fieldErrors["name"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-name`}>
                {t("Your name")}
              </FieldLabel>
              <Input
                id={`${fieldId}-name`}
                name="name"
                required
                maxLength={200}
                autoComplete="name"
              />
            </Field>
            <Field data-invalid={form.fieldErrors["email"] ? true : undefined}>
              <FieldLabel htmlFor={`${fieldId}-email`}>{t("Email")}</FieldLabel>
              <Input
                id={`${fieldId}-email`}
                name="email"
                type="email"
                required
                maxLength={320}
                autoComplete="email"
              />
            </Field>
            <Field>
              <FieldLabel htmlFor={`${fieldId}-notes`}>
                {t("Anything to share before the meeting")}
              </FieldLabel>
              <Textarea id={`${fieldId}-notes`} name="notes" maxLength={2000} />
            </Field>
            {error ? <FieldError>{error}</FieldError> : null}
          </FieldGroup>
          <div className="flex justify-end gap-2">
            <Button
              type="button"
              variant="outline"
              onClick={() => {
                setPicked(null);
              }}
            >
              {t("Pick another time")}
            </Button>
            <Button type="submit" disabled={form.pending}>
              {t("Book")}
            </Button>
          </div>
        </form>
      ) : (
        <p className="text-sm text-muted-foreground">
          {t("Pick a time to continue.")}
        </p>
      )}
    </div>
  );
}
