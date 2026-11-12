"use client";

import { useExtracted } from "next-intl";
import { useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { beginChatLink, unlinkIdentity } from "../identities-actions";

/** Removes one linked identity. */
export function UnlinkButton({ id }: { id: string }) {
  const t = useExtracted("identities");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      variant="ghost"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const result = await unlinkIdentity({ id });

          if (result.ok) {
            toast.success(t("Identity removed"));
          } else {
            toast.error(errorMessage(result.error));
          }
        });
      }}
    >
      {t("Remove")}
    </Button>
  );
}

type Provider = "slack" | "telegram" | "whatsapp";

const PROVIDERS: readonly { value: Provider; label: string }[] = [
  { value: "slack", label: "Slack" },
  { value: "telegram", label: "Telegram" },
  { value: "whatsapp", label: "WhatsApp" },
];

/** Issues a one-time code to send to the bot from the chat account. */
export function LinkChatForm() {
  const t = useExtracted("identities");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();
  const [provider, setProvider] = useState<Provider>("slack");
  const [code, setCode] = useState<string | null>(null);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <fieldset className="flex items-center gap-1">
        <legend className="sr-only">{t("Chat provider")}</legend>
        {PROVIDERS.map((option) => (
          <Button
            key={option.value}
            type="button"
            size="sm"
            variant={provider === option.value ? "secondary" : "ghost"}
            aria-pressed={provider === option.value}
            onClick={() => {
              setProvider(option.value);
            }}
          >
            {option.label}
          </Button>
        ))}
      </fieldset>
      <Button
        size="sm"
        variant="outline"
        disabled={pending}
        onClick={() => {
          startTransition(async () => {
            const result = await beginChatLink({ provider });

            if (result.ok) {
              setCode(result.data.code);
            } else {
              toast.error(errorMessage(result.error));
            }
          });
        }}
      >
        {t("Get link code")}
      </Button>
      {code === null ? null : (
        <p className="text-sm">
          {t("Send this code to the bot:")}{" "}
          <code className="rounded bg-muted px-1.5 py-0.5 font-mono text-xs">
            {code}
          </code>
        </p>
      )}
    </div>
  );
}
