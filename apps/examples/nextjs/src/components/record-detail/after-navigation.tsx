import type { ReactNode } from "react";

import { navigation } from "next/cache";

/**
 * Holds a heavy section back until the navigation commits, so a prefetch of the
 * record page carries the head and the skeletons but none of the section reads.
 * Wrap it in `<Suspense fallback={<RecordSectionSkeleton />}>`.
 */
export async function AfterNavigation({ children }: { children: ReactNode }) {
  await navigation();

  return children;
}
