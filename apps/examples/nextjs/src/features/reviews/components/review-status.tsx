"use client";

import { useExtracted } from "next-intl";

import { Badge } from "@/components/reui/badge";

import type { ReviewRow } from "../review-row";

export function useReviewStatusLabel(): (status: string) => string {
  const t = useExtracted("reviews");

  return (status) => {
    switch (status) {
      case "pending": {
        return t("Pending");
      }

      case "published": {
        return t("Published");
      }

      case "rejected": {
        return t("Rejected");
      }

      default: {
        return status;
      }
    }
  };
}

export function ReviewStatusBadge({ status }: { status: ReviewRow["status"] }) {
  const label = useReviewStatusLabel();

  switch (status) {
    case "pending": {
      return <Badge variant="warning-light">{label(status)}</Badge>;
    }

    case "published": {
      return <Badge variant="success-light">{label(status)}</Badge>;
    }

    case "rejected": {
      return <Badge variant="destructive-light">{label(status)}</Badge>;
    }

    default: {
      const never: never = status;

      return never;
    }
  }
}

/** The rating as filled stars in text, readable without color. */
export function RatingText({ rating }: { rating: number }) {
  return (
    <span className="tabular-nums" aria-label={`${rating} / 5`}>
      {"★".repeat(rating)}
      <span className="text-muted-foreground">{"★".repeat(5 - rating)}</span>
    </span>
  );
}
