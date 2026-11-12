"use client";

import { useExtracted } from "next-intl";
import { useTransition } from "react";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import { archiveEntry, publishEntry } from "../content-actions";

/** Publish and archive for one entry; the server checks `content.publish`. */
export function ContentRowActions({
  entryId,
  status,
}: {
  entryId: string;
  status: "archived" | "draft" | "published" | "scheduled";
}) {
  const t = useExtracted("content");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex justify-end gap-2">
      {status === "draft" || status === "scheduled" ? (
        <Button
          size="sm"
          variant="outline"
          disabled={pending}
          onClick={() => {
            startTransition(async () => {
              const result = await publishEntry({ entryId });

              if (result.ok) {
                toast.success(t("Entry published"));
              } else {
                toast.error(errorMessage(result.error));
              }
            });
          }}
        >
          {t("Publish")}
        </Button>
      ) : null}
      {status === "archived" ? null : (
        <Button
          size="sm"
          variant="ghost"
          disabled={pending}
          onClick={() => {
            startTransition(async () => {
              const result = await archiveEntry({ entryId });

              if (result.ok) {
                toast.success(t("Entry archived"));
              } else {
                toast.error(errorMessage(result.error));
              }
            });
          }}
        >
          {t("Archive")}
        </Button>
      )}
    </div>
  );
}
