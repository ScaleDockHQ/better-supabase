import type { BlockSqlContext } from "../context.ts";
import type { ApprovalContribution } from "../contributions.ts";
import type { ApprovalPolicy } from "./approvals-policies.ts";
import type { TaskNames } from "./tasks-functions.ts";

import { sqlString } from "../../core/template.ts";
import { subjectUuid } from "../contributions.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { stageByCategory, taskRecord } from "./tasks-coordination-shared.ts";

/** The subject type of an approval a hold opens. */
export const HOLD_SUBJECT = "task_hold";

const WHERE = "blocks.tasks.options.hold.approval";

/** What `hold.approval` resolves to. */
export interface HoldApproval {
  /** The policy snapshot the request stores, as JSON text. */
  readonly policy: string;
  /** What a rejection does: cancel the task, or leave it on hold. */
  readonly onReject: "cancel" | "keep";
  /** The hold kinds that open an approval, or null for every kind. */
  readonly kinds: readonly string[] | null;
}

/** What a hold kind looks like: a short lowercase word. */
const HOLD_KIND: RegExp = /^[a-z][a-z_]{0,31}$/;

/** Reads a list of hold kinds: `hold.kinds` or `hold.approval.kinds`. */
export function holdKindsOf(
  value: unknown,
  at: string,
): readonly string[] | null {
  if (value === undefined) {
    return null;
  }

  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    !value.every(
      (kind): kind is string =>
        typeof kind === "string" && HOLD_KIND.test(kind),
    ) ||
    new Set(value).size !== value.length
  ) {
    throw new TypeError(
      `${at} must be a list of distinct short lowercase words such as review or input`,
    );
  }

  return value;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Whether `hold.approval` is set, without resolving its policy. */
export function holdApprovalOn(ctx: BlockSqlContext): boolean {
  const hold = ctx.option("hold");

  return (
    isRecord(hold) &&
    hold["approval"] !== undefined &&
    hold["approval"] !== false
  );
}

/**
 * Reads `hold.approval`: `true` for one approver step (members with the manage
 * permission), or `{ policy, onReject }`. Needs the approvals block.
 */
export function holdApprovalOf(
  ctx: BlockSqlContext,
  value: unknown,
  manageKey: string,
  holdKinds: readonly string[] | null = null,
): HoldApproval | null {
  if (value === undefined || value === false) {
    return null;
  }

  const rules = value === true ? {} : value;

  if (!isRecord(rules)) {
    throw new TypeError(`${WHERE} must be true or an object`);
  }

  for (const key of Object.keys(rules)) {
    if (key !== "policy" && key !== "onReject" && key !== "kinds") {
      throw new TypeError(`${WHERE} has no key "${key}"`);
    }
  }

  if (!ctx.installed("approvals")) {
    throw new TypeError(`${WHERE} needs the approvals block`);
  }

  if (!ctx.has("items", "heldAt")) {
    throw new TypeError(
      `${WHERE} needs the held_at column: add it to your tasks table, or run better-supabase codemod owned-columns`,
    );
  }

  const onReject = rules["onReject"] ?? "cancel";

  if (onReject !== "cancel" && onReject !== "keep") {
    throw new TypeError(`${WHERE}.onReject must be "cancel" or "keep"`);
  }

  const policy: ApprovalPolicy = policyOf(
    HOLD_SUBJECT,
    "approve",
    rules["policy"] ?? { steps: [{ approvers: { permission: manageKey } }] },
    `${WHERE}.policy`,
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.policy.run is not allowed; the decision releases or cancels the task`,
    );
  }

  const kinds = holdKindsOf(rules["kinds"], `${WHERE}.kinds`);

  const stray = kinds?.find((kind) => holdKinds?.includes(kind) === false);

  if (stray !== undefined) {
    throw new TypeError(
      `${WHERE}.kinds names "${stray}", which blocks.tasks.options.hold.kinds does not allow`,
    );
  }

  return { policy: policySnapshot(policy), onReject, kinds };
}

/**
 * The function approvals calls with a decision. It isn't granted to anyone: the
 * decider needs no task permission, only the approval.
 */
export function settleHoldSql(ctx: BlockSqlContext, n: TaskNames): string {
  if (n.co.holdApproval === null) {
    return "";
  }

  const w = (column: string): string => n.c("items", column);
  const fn = n.fn("settle_task_hold");
  const kind = ctx.has("items", "holdKind");
  const back = ctx.has("items", "holdReturnStage");

  const clear = [
    `${w("heldAt")} = null`,
    kind ? `${w("holdKind")} = null` : "",
    back ? `${w("holdReturnStage")} = null` : "",
    n.co.holdStage !== null && back
      ? `${w("stage")} = coalesce(x.${w("holdReturnStage")}, x.${w("stage")})`
      : "",
  ].filter((set) => set !== "");

  return `
-- Applies an approval's decision to a held task: release it, or cancel it.
-- Approvals calls it; it isn't granted to anyone. A task that is no longer on
-- hold is left alone.
create or replace function ${fn}(task uuid, outcome text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${n.t("items")};
  v_stage uuid;
begin
  select * into v_row from ${n.t("items")} x where x.${w("id")} = settle_task_hold.task for update;
  if not found or v_row.${w("heldAt")} is null then
    return;
  end if;
  if settle_task_hold.outcome = 'cancel' then
    v_stage := ${stageByCategory(ctx, `v_row.${w("pipeline")}`, "canceled")};
  end if;
  if v_stage is not null then
    perform set_config('bsb.close_note', 'The hold was rejected', true);
    update ${n.t("items")} x set ${w("stage")} = v_stage where x.${w("id")} = v_row.${w("id")};
    perform set_config('bsb.close_note', '', true);
    return;
  end if;
  update ${n.t("items")} x set ${clear.join(", ")} where x.${w("id")} = v_row.${w("id")} returning * into v_row;
  ${taskRecord(ctx, n, "task.hold_released", "v_row", `, 'returnStageId', v_row.${w("stage")}, 'approved', settle_task_hold.outcome = 'release'`)}
end;
$$;
revoke execute on function ${fn}(uuid, text) from public, anon, authenticated;
`;
}

/** Approvals decides holds: approval releases the task, rejection cancels it. */
export function holdApprovalContribution(
  own: BlockSqlContext,
  holdApproval: HoldApproval | null,
): readonly ApprovalContribution[] {
  if (holdApproval === null) {
    return [];
  }

  const settle = own.fn("settle_task_hold");

  return [
    {
      subject: HOLD_SUBJECT,
      access: "declared",
      filedBy: "block",
      approvable: ({ subjectId }) =>
        `exists (select 1 from ${own.table("items")} x where x.${own.col("items", "id")} = ${subjectUuid(subjectId)} and x.${own.col("items", "heldAt")} is not null)`,
      approve: ({ subjectId }) =>
        `perform ${settle}(${subjectUuid(subjectId)}, 'release');`,
      ...(holdApproval.onReject === "cancel"
        ? {
            reject: ({ subjectId }: { readonly subjectId: string }) =>
              `perform ${settle}(${subjectUuid(subjectId)}, 'cancel');`,
          }
        : {}),
    },
  ];
}

/**
 * PL/pgSQL that cancels the pending approval request of a held task, for a path
 * that ends the hold without a decision (release, the hold stage left, a
 * close). `found` tells whether a request was cancelled. Empty when holds open
 * no approval.
 */
export function cancelHoldRequestSql(
  ctx: BlockSqlContext,
  n: TaskNames,
  task: string,
): string {
  if (n.co.holdApproval === null) {
    return "";
  }

  const ap = ctx.of("approvals");
  const c = (column: string): string => ap.col("requests", column);

  const decided = ap.has("requests", "decidedAt")
    ? `, ${c("decidedAt")} = now()`
    : "";

  return `update ${ap.table("requests")} r set ${c("status")} = 'cancelled'${decided}
    where r.${c("subjectType")} = ${sqlString(HOLD_SUBJECT)} and r.${c("subjectId")} = ${task}::text and r.${c("status")} = 'pending';`;
}
