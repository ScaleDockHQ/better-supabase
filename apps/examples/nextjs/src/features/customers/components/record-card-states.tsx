"use client";

import { RecordSectionError } from "@/components/record-detail/record-section-error";

import { retryCustomerRecord } from "../customers-actions";

export { RecordSectionSkeleton as RecordCardSkeleton } from "@/components/record-detail/record-section-states";

/** The inline error of a customer page card, with Retry. */
export function RecordLoadError({ title }: { title: string }) {
  return <RecordSectionError title={title} retryAction={retryCustomerRecord} />;
}
