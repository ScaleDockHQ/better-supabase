"use client";

import { useExtracted } from "next-intl";
import { useState, useTransition } from "react";

import { Button } from "@/components/ui/button";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
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

/** Issues a one-time code to send to the bot from the chat account. */
export function LinkChatForm() {
  const t = useExtracted("identities");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();
  const [provider, setProvider] = useState<Provider>("slack");
  const [code, setCode] = useState<string | null>(null);

  return (
    <div className="flex flex-wrap items-center gap-2">
      <Select
        value={provider}
        onValueChange={(next) => {
          if (next === "slack" || next === "telegram" || next === "whatsapp") {
            setProvider(next);
          }
        }}
        items={{ slack: "Slack", telegram: "Telegram", whatsapp: "WhatsApp" }}
      >
        <SelectTrigger className="w-40" aria-label={t("Chat provider")}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="slack">Slack</SelectItem>
          <SelectItem value="telegram">Telegram</SelectItem>
          <SelectItem value="whatsapp">WhatsApp</SelectItem>
        </SelectContent>
      </Select>
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
