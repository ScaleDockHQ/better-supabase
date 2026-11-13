"use client";

import { useAction, useErrorMessage } from "better-supabase/react";
import { Trash2Icon } from "lucide-react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { clearAiCache } from "../ai-usage-actions";

/** Deletes the organization's cached model calls. */
export function ClearCacheButton() {
  const t = useExtracted("aiUsage");
  const errorMessage = useErrorMessage();

  const clear = useAction(clearAiCache, {
    onSuccess: (count) => {
      toast.success(t("Cleared {count, number} cached calls", { count }));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={clear.pending}
      onClick={() => {
        void clear.run({});
      }}
    >
      <Trash2Icon />
      {t("Clear the call cache")}
    </Button>
  );
}
