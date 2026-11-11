"use client";

import type { CellContext } from "@tanstack/react-table";

import { StarIcon } from "lucide-react";
import { useExtracted, useFormatter } from "next-intl";

import type { RecordListColumns } from "@/components/record-list/record-list-grid";
import type { RecordListPage } from "@/components/record-list/record-list-types";
import type { ReadOnlyGridFeatures } from "@/components/reui/data-grid/data-grid";

import { RecordListView } from "@/components/record-list/record-list-view";
import { Link } from "@/i18n/navigation";

import type { ReviewRow } from "../review-row";

import { REVIEW_STATUSES } from "../reviews-list";
import { useReviewListState } from "../use-review-list-state";
import {
  RatingText,
  ReviewStatusBadge,
  useReviewStatusLabel,
} from "./review-status";

type ReviewCell = CellContext<ReadOnlyGridFeatures, ReviewRow>;

function ReviewCellTitle({ row }: ReviewCell) {
  const t = useExtracted("reviews");
  const { id, title, excerpt } = row.original;

  return (
    <div className="flex flex-col">
      <Link
        href={`/shop/reviews/${id}`}
        className="font-medium hover:underline"
      >
        {title ?? excerpt ?? t("Rating only")}
      </Link>
      {title !== null && excerpt !== null ? (
        <span className="truncate text-xs text-muted-foreground">
          {excerpt}
        </span>
      ) : null}
    </div>
  );
}

function RatingCell({ row }: ReviewCell) {
  return <RatingText rating={row.original.rating} />;
}

function StatusCell({ row }: ReviewCell) {
  return <ReviewStatusBadge status={row.original.status} />;
}

function DateCell({ row }: ReviewCell) {
  const format = useFormatter();

  return (
    <span className="text-muted-foreground">
      {format.dateTime(new Date(row.original.createdAt), {
        dateStyle: "medium",
      })}
    </span>
  );
}

/** The review moderation queue on the list kit; the URL holds the status. */
export function ReviewRecordList({
  initial,
}: {
  initial: RecordListPage<ReviewRow>;
}) {
  const t = useExtracted("reviews");
  const statusLabel = useReviewStatusLabel();
  const list = useReviewListState();

  const columns: RecordListColumns<ReviewRow> = [
    {
      accessorKey: "title",
      header: t("Review"),
      size: 340,
      cell: ReviewCellTitle,
    },
    { accessorKey: "rating", header: t("Rating"), size: 120, cell: RatingCell },
    { accessorKey: "author", header: t("Author"), size: 160 },
    { accessorKey: "status", header: t("Status"), size: 130, cell: StatusCell },
    {
      accessorKey: "createdAt",
      header: t("Written"),
      size: 140,
      cell: DateCell,
    },
  ];

  return (
    <RecordListView
      list={list}
      endpoint="/api/reviews/list"
      initial={initial}
      columns={columns}
      facets={[
        {
          key: "status",
          label: t("Status"),
          valueLabel: statusLabel,
          values: REVIEW_STATUSES,
        },
      ]}
      sorts={[{ value: "newest", label: t("Newest first") }]}
      emptyIcon={<StarIcon />}
      emptyTitle={t("No reviews found")}
      emptyDescription={t(
        "Reviews written on the store show here for moderation.",
      )}
    />
  );
}
