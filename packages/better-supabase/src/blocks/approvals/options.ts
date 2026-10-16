import { type BlockOptionsSchema, blockOptions, option } from "../options.ts";

/** `blocks.approvals.options`. */
export type ApprovalsSqlOptions = {
  readonly subjects?: unknown;
  readonly policies?: unknown;
  readonly extraColumns?: unknown;
};

export const approvalsSqlOptions: BlockOptionsSchema<ApprovalsSqlOptions> =
  blockOptions<ApprovalsSqlOptions>({
    subjects: option.unknown(),
    policies: option.unknown(),
    extraColumns: option.unknown(),
  });
