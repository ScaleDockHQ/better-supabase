import type { BlockOptionsSchema, ExtraColumns } from "../options.ts";

import { blockOptions, option } from "../options.ts";

export type HiringStageMarker =
  | string
  | { readonly column: string; readonly value: string };

export type HiringJobStages = {
  readonly table: string;
  readonly id?: string;
  readonly job: string;
  readonly rank: string;
  readonly archivedAt?: string;
  readonly hired?: HiringStageMarker;
  readonly rejected?: HiringStageMarker;
  readonly withdrawn?: HiringStageMarker;
};

/** `blocks.hiring.options`. */
export type HiringSqlOptions = {
  readonly candidate?: string;
  readonly extraColumns?: ExtraColumns;
  readonly stages?: "pipelines" | HiringJobStages;
  readonly scorecardKey?: "stage" | "application";
  readonly hiringManager?: "user" | "employee";
};

export const hiringSqlOptions: BlockOptionsSchema<HiringSqlOptions> =
  blockOptions<HiringSqlOptions>({
    candidate: option.string({ default: "person" }),
    extraColumns: option.extraColumns(),
    stages: option.unknown({ default: "pipelines" }),
    scorecardKey: option.string({ default: "stage" }),
    hiringManager: option.string({ default: "user" }),
  });
