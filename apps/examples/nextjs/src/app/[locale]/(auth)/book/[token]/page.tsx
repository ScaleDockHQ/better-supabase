import { Suspense } from "react";

import {
  BookingPage,
  BookingPageSkeleton,
} from "@/features/bookings/components/booking-page";

export default function BookPage({
  params,
  searchParams,
}: PageProps<"/[locale]/book/[token]">) {
  return (
    <Suspense fallback={<BookingPageSkeleton />}>
      <BookingPage params={params} searchParams={searchParams} />
    </Suspense>
  );
}
