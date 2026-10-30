import type { ProductionOrderStatus } from "better-supabase/blocks/manufacturing";

/** The statuses the board shows a column for; canceled orders drop off it. */
export const BOARD_STATUSES = [
  "draft",
  "released",
  "in_progress",
  "done",
] as const satisfies readonly ProductionOrderStatus[];

export type BoardStatus = (typeof BOARD_STATUSES)[number];

export const isBoardStatus = (
  status: ProductionOrderStatus,
): status is BoardStatus => status !== "canceled";
