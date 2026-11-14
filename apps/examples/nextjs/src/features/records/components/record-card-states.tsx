"use client";

import { RecordSectionError } from "@/components/record-detail/record-section-error";

import { retryRecord } from "../records-actions";

export { RecordSectionSkeleton as RecordCardSkeleton } from "@/components/record-detail/record-section-states";

/** The inline error of a record page card, with Retry. */
export function RecordLoadError({ title }: { title: string }) {
  return <RecordSectionError title={title} retryAction={retryRecord} />;
}
