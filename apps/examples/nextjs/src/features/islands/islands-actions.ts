"use server";

import { refresh } from "next/cache";

/** Re-renders the islands page so a failed island reads again. */
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryIslands() {
  refresh();
}
