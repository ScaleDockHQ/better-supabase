"use client";

import { useExtracted } from "next-intl";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { decideItem } from "../moderation-actions";

type Decision = "approve" | "hide" | "remove" | "restore";

/** The decisions a moderator can make on one item. */
export function DecideButtons({
  itemId,
  decisions,
}: {
  itemId: string;
  decisions: readonly Decision[];
}) {
  const t = useExtracted("moderation");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  const labels: Record<Decision, string> = {
    approve: t("Approve"),
    hide: t("Hide"),
    remove: t("Remove"),
    restore: t("Restore"),
  };

  return (
    <div className="flex justify-end gap-2">
      {decisions.map((decision) => (
        <Button
          key={decision}
          size="sm"
          variant={decision === "remove" ? "destructive" : "outline"}
          disabled={pending}
          onClick={() => {
            startTransition(async () => {
              const result = await decideItem({ itemId, decision });

              if (result.ok) {
                toast.success(t("Decision saved"));
              } else {
                toast.error(errorMessage(result.error));
              }
            });
          }}
        >
          {labels[decision]}
        </Button>
      ))}
    </div>
  );
}
