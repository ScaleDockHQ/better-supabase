"use client";

import { useErrorMessage } from "better-supabase/react";
import { useExtracted } from "next-intl";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";

import { publishAdvisory } from "../advisories-actions";

/** Publishes a draft advisory; the server checks `advisories.publish`. */
export function PublishAdvisoryButton({ id }: { id: string }) {
  const t = useExtracted("advisories");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      variant="outline"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const result = await publishAdvisory({ id });

          if (result.ok) {
            toast.success(t("Advisory published"));
          } else {
            toast.error(errorMessage(result.error));
          }
        });
      }}
    >
      {t("Publish")}
    </Button>
  );
}
