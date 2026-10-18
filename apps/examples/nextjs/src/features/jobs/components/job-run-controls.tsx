"use client";

import { ListPlusIcon } from "lucide-react";
import { useExtracted } from "next-intl";
import { useTransition } from "react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useErrorMessage } from "@/lib/use-error-message";

import { enqueueTestJob, retryJobRun } from "../jobs-actions";

export function EnqueueTestJobButton({
  variant = "default",
}: {
  variant?: "default" | "outline";
}) {
  const t = useExtracted("jobs");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      size="sm"
      variant={variant}
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const queued = await enqueueTestJob({});

          if (queued.ok) {
            toast.success(t("Test job queued"));
          } else {
            toast.error(errorMessage(queued.error));
          }
        });
      }}
    >
      <ListPlusIcon />
      {t("Enqueue a test job")}
    </Button>
  );
}

/** Queues a dead job again. */
export function RetryJobButton({ queue, id }: { queue: string; id: number }) {
  const t = useExtracted("jobs");
  const errorMessage = useErrorMessage();
  const [pending, startTransition] = useTransition();

  return (
    <Button
      variant="outline"
      size="sm"
      disabled={pending}
      onClick={() => {
        startTransition(async () => {
          const retried = await retryJobRun({ queue, id });

          if (retried.ok) {
            toast.success(t("Job queued again"));
          } else {
            toast.error(errorMessage(retried.error));
          }
        });
      }}
    >
      {t("Retry")}
    </Button>
  );
}
