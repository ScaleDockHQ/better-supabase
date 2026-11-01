import type { ReadType } from "../../core/read-type.ts";
import type { BlockSqlRead } from "../reads.ts";

import { declareRead } from "../reads.ts";

/** What `deal_board` returns: a pipeline's stages with their deals and totals. */
export const DEAL_BOARD_RESULT: ReadType = {
  pipelineId: "text",
  stages: [
    {
      id: "text",
      key: "text",
      name: "text",
      category: "text",
      probability: "number?",
      rottingAfterDays: "number?",
      wipLimit: "number?",
      count: "number",
      totals: [{ currency: "text", amount: "text", weighted: "text" }],
      deals: [
        {
          id: "text",
          identifier: "text",
          name: "text",
          amount: "text",
          currency: "text",
          ownerId: "text?",
          closeOn: "text",
          probability: "number?",
          daysInStage: "number",
          rotting: "bool",
          nextStep: "text?",
          nextAt: "text?",
          rank: "text",
        },
      ],
    },
  ],
  weighted: [{ currency: "text", amount: "text" }],
};

export interface DealBoardMoney {
  readonly currency: string;
  readonly amount: string;
  readonly weighted: string;
}

export interface DealCard {
  readonly id: string;
  readonly identifier: string;
  readonly name: string;
  readonly amount: string;
  readonly currency: string;
  readonly ownerId: string | null;
  readonly closeOn: string;
  readonly probability: number | null;
  readonly daysInStage: number;
  readonly rotting: boolean;
  readonly nextStep: string | null;
  readonly nextAt: string | null;
  readonly rank: string;
}

export interface DealBoardStage {
  readonly id: string;
  readonly key: string;
  readonly name: string;
  readonly category: string;
  readonly probability: number | null;
  readonly rottingAfterDays: number | null;
  readonly wipLimit: number | null;
  readonly count: number;
  readonly totals: readonly DealBoardMoney[];
  readonly deals: readonly DealCard[];
}

/** What `deals.board` returns. Keep it in step with `DEAL_BOARD_RESULT`. */
export interface DealBoard {
  readonly pipelineId: string;
  readonly stages: readonly DealBoardStage[];
  readonly weighted: readonly {
    readonly currency: string;
    readonly amount: string;
  }[];
}

export const DEAL_READS: readonly BlockSqlRead[] = [
  declareRead(
    "board",
    "deal_board",
    { pipelineId: { param: "pipeline", type: "id" } },
    DEAL_BOARD_RESULT,
    "A pipeline's stages with their deals, counts, totals per currency and the weighted forecast.",
  ),
];
