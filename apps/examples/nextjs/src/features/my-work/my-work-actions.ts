"use server";

import { refresh } from "next/cache";

/** Reads My work again, for the list's Retry button. */
// oxlint-disable-next-line typescript/require-await -- a Server Action must be async, and refresh() returns nothing to await
export async function retryMyWork(): Promise<void> {
  refresh();
}
