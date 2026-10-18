"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useRouter } from "@/i18n/navigation";
import { useErrorMessage } from "@/lib/use-error-message";

import type { QuoteStatus } from "../crm-queries";

import { decideQuote, reviseQuote, sendQuote } from "../crm-actions";

/** What the quote's status allows: send a draft, record the answer, revise. */
export function QuoteStatusActions({
  quoteId,
  status,
  hasLines,
}: {
  quoteId: string;
  status: QuoteStatus;
  hasLines: boolean;
}) {
  const t = useExtracted("crm");
  const router = useRouter();
  const errorMessage = useErrorMessage();

  const onError = (error: Parameters<typeof errorMessage>[0]) => {
    toast.error(errorMessage(error));
  };

  const send = useAction(sendQuote, {
    onSuccess: () => {
      toast.success(t("Quote sent"));
    },
    onError,
  });

  const decide = useAction(decideQuote, {
    onSuccess: () => {
      toast.success(t("Answer recorded"));
    },
    onError,
  });

  const revise = useAction(reviseQuote, {
    onSuccess: (quote) => {
      toast.success(t("New revision started"));
      router.push(`/crm/quotes/${quote.id}`);
    },
    onError,
  });

  const pending = send.pending || decide.pending || revise.pending;
  const awaiting = status === "sent" || status === "viewed";
  const revisable = awaiting || status === "rejected" || status === "expired";

  if (status !== "draft" && !awaiting && !revisable) {
    return null;
  }

  return (
    <div className="flex flex-wrap gap-2">
      {status === "draft" ? (
        <Button
          type="button"
          size="sm"
          disabled={pending || !hasLines}
          onClick={() => {
            void send.run({ quoteId });
          }}
        >
          {t("Send for acceptance")}
        </Button>
      ) : null}
      {awaiting ? (
        <>
          <Button
            type="button"
            size="sm"
            disabled={pending}
            onClick={() => {
              void decide.run({ quoteId, decision: "accepted" });
            }}
          >
            {t("Mark accepted")}
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={pending}
            onClick={() => {
              void decide.run({ quoteId, decision: "changes_requested" });
            }}
          >
            {t("Changes requested")}
          </Button>
          <Button
            type="button"
            size="sm"
            variant="outline"
            disabled={pending}
            onClick={() => {
              void decide.run({ quoteId, decision: "rejected" });
            }}
          >
            {t("Mark rejected")}
          </Button>
        </>
      ) : null}
      {revisable ? (
        <Button
          type="button"
          size="sm"
          variant="ghost"
          disabled={pending}
          onClick={() => {
            void revise.run({ quoteId });
          }}
        >
          {t("Revise")}
        </Button>
      ) : null}
    </div>
  );
}
