"use client";

import { useAction } from "better-supabase/react";
import { KeyRoundIcon, Trash2Icon, ZapIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useId, useState } from "react";
import { toast } from "sonner";
import * as v from "valibot";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Field, FieldLabel } from "@/components/ui/field";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import {
  Sheet,
  SheetContent,
  SheetDescription,
  SheetHeader,
  SheetTitle,
  SheetTrigger,
} from "@/components/ui/sheet";
import { useErrorMessage } from "@/lib/use-error-message";

import type { TriggerRow } from "../builder-queries";

import {
  removeTrigger,
  rotateWebhookToken,
  saveTrigger,
} from "../builder-actions";

const KINDS = ["webhook", "schedule", "event", "manual"] as const;
const Kind = v.picklist(KINDS);
type Kind = v.InferOutput<typeof Kind>;

const summary = (trigger: TriggerRow): string => {
  const { cron, type } = trigger.config;
  if (v.is(v.string(), cron)) return cron;
  if (v.is(v.string(), type)) return type;
  return "";
};

export function TriggerSheet({
  definition,
  triggers,
}: {
  definition: string;
  triggers: readonly TriggerRow[];
}) {
  const t = useExtracted("workflows");
  const id = useId();
  const errorMessage = useErrorMessage();
  const [kind, setKind] = useState<Kind>("webhook");
  const [webhookUrl, setWebhookUrl] = useState<string | null>(null);
  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };
  const save = useAction(saveTrigger, {
    onError,
    onSuccess: () => {
      toast.success(t("Trigger saved"));
    },
  });
  const remove = useAction(removeTrigger, { onError });
  const rotate = useAction(rotateWebhookToken, {
    onError,
    onSuccess: (token) => {
      setWebhookUrl(
        `${window.location.origin}/api/workflows/hooks/${encodeURIComponent(token)}`,
      );
    },
  });
  const labels = {
    webhook: t("Webhook"),
    schedule: t("Schedule"),
    event: t("Event"),
    manual: t("Manual"),
  } satisfies Record<Kind, string>;
  return (
    <Sheet>
      <SheetTrigger render={<Button variant="outline" size="sm" />}>
        <ZapIcon />
        {t("Triggers")}
      </SheetTrigger>
      <SheetContent className="gap-6 p-6">
        <SheetHeader className="p-0">
          <SheetTitle>{t("Triggers")}</SheetTitle>
          <SheetDescription>
            {t(
              "What starts the published version besides the Run button. A webhook's URL is shown once.",
            )}
          </SheetDescription>
        </SheetHeader>
        <ul className="space-y-2">
          {triggers.map((trigger) => (
            <li
              key={trigger.id}
              className="flex items-center justify-between gap-2 text-sm"
            >
              <span className="flex min-w-0 items-center gap-2">
                <Badge variant="secondary">
                  {v.is(Kind, trigger.kind)
                    ? labels[trigger.kind]
                    : trigger.kind}
                </Badge>
                <span className="text-muted-foreground truncate font-mono text-xs">
                  {summary(trigger)}
                </span>
              </span>
              <span className="flex gap-1">
                {trigger.kind === "webhook" ? (
                  <Button
                    variant="ghost"
                    size="sm"
                    aria-label={t("New webhook URL")}
                    disabled={rotate.pending}
                    onClick={() => {
                      void rotate.run({ id: trigger.id });
                    }}
                  >
                    <KeyRoundIcon />
                  </Button>
                ) : null}
                <Button
                  variant="ghost"
                  size="sm"
                  aria-label={t("Remove")}
                  disabled={remove.pending}
                  onClick={() => {
                    void remove.run({ id: trigger.id });
                  }}
                >
                  <Trash2Icon />
                </Button>
              </span>
            </li>
          ))}
        </ul>
        {webhookUrl ? (
          <Field>
            <FieldLabel htmlFor={`${id}-url`}>{t("Webhook URL")}</FieldLabel>
            <Input
              id={`${id}-url`}
              value={webhookUrl}
              readOnly
              className="font-mono text-xs"
            />
          </Field>
        ) : null}
        <form
          className="space-y-3"
          action={(form) => {
            void save.run({
              definition,
              kind,
              cron: String(form.get("cron") ?? ""),
              event: String(form.get("event") ?? ""),
            });
          }}
        >
          <Field>
            <FieldLabel htmlFor={`${id}-kind`}>{t("Kind")}</FieldLabel>
            <Select
              value={kind}
              onValueChange={(value) => {
                if (v.is(Kind, value)) setKind(value);
              }}
              items={KINDS.map((value) => ({ value, label: labels[value] }))}
            >
              <SelectTrigger id={`${id}-kind`}>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {KINDS.map((value) => (
                  <SelectItem key={value} value={value}>
                    {labels[value]}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          {kind === "schedule" ? (
            <Field>
              <FieldLabel htmlFor={`${id}-cron`}>{t("Cron")}</FieldLabel>
              <Input
                id={`${id}-cron`}
                name="cron"
                defaultValue="0 9 * * *"
                className="font-mono"
              />
            </Field>
          ) : null}
          {kind === "event" ? (
            <Field>
              <FieldLabel htmlFor={`${id}-event`}>{t("Event type")}</FieldLabel>
              <Input
                id={`${id}-event`}
                name="event"
                placeholder="customer.created"
                className="font-mono"
              />
            </Field>
          ) : null}
          <Button type="submit" disabled={save.pending}>
            {t("Add trigger")}
          </Button>
        </form>
      </SheetContent>
    </Sheet>
  );
}
