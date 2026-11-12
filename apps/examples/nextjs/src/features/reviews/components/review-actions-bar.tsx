"use client";

import { useAction } from "better-supabase/react";
import { useExtracted } from "next-intl";

import { Button } from "@/components/ui/button";
import { toast } from "@/lib/toast";
import { useErrorMessage } from "@/lib/use-error-message";

import type { ReviewRow } from "../review-row";

import { publishReview } from "../reviews-actions";
import { ReviewResponseDialog } from "./review-response-dialog";

/** Publish, reject or reply from the detail head. */
export function ReviewActionsBar({
  reviewId,
  status,
}: {
  reviewId: string;
  status: ReviewRow["status"];
}) {
  const t = useExtracted("reviews");
  const errorMessage = useErrorMessage();

  const publish = useAction(publishReview, {
    onSuccess: () => {
      toast.success(t("Review published"));
    },
    onError: (error) => {
      toast.error(errorMessage(error));
    },
  });

  return (
    <>
      {status === "published" ? null : (
        <Button
          size="sm"
          disabled={publish.pending}
          onClick={() => {
            void publish.run({ reviewId });
          }}
        >
          {t("Publish")}
        </Button>
      )}
      {status === "rejected" ? null : (
        <ReviewResponseDialog reviewId={reviewId} kind="reject" />
      )}
      {status === "published" ? (
        <ReviewResponseDialog reviewId={reviewId} kind="reply" />
      ) : null}
    </>
  );
}
