import type { ModuleContext } from "../context.ts";

/** Who may decide one step. Any match is enough. */
export interface ApprovalApprovers {
  /** Holders of this permission in the request's tenant. */
  readonly permission?: string;
  /** Members with this membership role. */
  readonly role?: string;
  /** Members of this team (the `teams` module). */
  readonly team?: string;
  /** These user ids. */
  readonly users?: readonly string[];
}

export interface ApprovalStep {
  readonly approvers: ApprovalApprovers;
  /** Approvals the step needs before the request moves on. */
  readonly required: number;
}

/** What the final approval runs. */
export type ApprovalRun =
  | { readonly kind: "transition"; readonly to: string }
  | { readonly kind: "queue"; readonly queue: string };

export interface ApprovalPolicy {
  readonly subjectType: string;
  readonly action: string;
  readonly steps: readonly ApprovalStep[];
  /** An ISO 8601 duration such as `P7D`. */
  readonly expiresIn?: string;
  readonly selfApproval: boolean;
  readonly run?: ApprovalRun;
}

const KEY = /^[a-z][a-z0-9_-]*$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const DURATION: RegExp =
  /^P(?=\d|T\d)(\d+Y)?(\d+M)?(\d+W)?(\d+D)?(T(?=\d)(\d+H)?(\d+M)?(\d+S)?)?$/;
const WHERE = "sql.modules.approvals.options.policies";

type Fields = Readonly<Record<string, unknown>>;

const isFields = (value: unknown): value is Fields =>
  typeof value === "object" && value !== null && !Array.isArray(value);

function approversOf(value: unknown, where: string): ApprovalApprovers {
  if (!isFields(value)) {
    throw new TypeError(
      `${where}.approvers must be an object with permission, role, team or users`,
    );
  }
  const text = (key: string): string | undefined => {
    const item = value[key];
    if (item === undefined) return undefined;
    if (typeof item !== "string" || item.trim() === "") {
      throw new TypeError(`${where}.approvers.${key} must be a string`);
    }
    return item;
  };
  const users = value["users"];
  if (
    users !== undefined &&
    (!Array.isArray(users) ||
      users.length === 0 ||
      !users.every((user) => typeof user === "string" && UUID.test(user)))
  ) {
    throw new TypeError(`${where}.approvers.users must be a list of user ids`);
  }
  const permission = text("permission");
  const role = text("role");
  const team = text("team");
  const approvers: ApprovalApprovers = {
    ...(permission === undefined ? {} : { permission }),
    ...(role === undefined ? {} : { role }),
    ...(team === undefined ? {} : { team }),
    ...(Array.isArray(users) ? { users: users.map(String) } : {}),
  };
  if (Object.keys(approvers).length === 0) {
    throw new TypeError(`${where}.approvers names nobody`);
  }
  return approvers;
}

function stepOf(value: unknown, where: string): ApprovalStep {
  if (!isFields(value)) throw new TypeError(`${where} must be an object`);
  const approvers = approversOf(value["approvers"], where);
  const required = value["required"] ?? 1;
  if (required === "all") {
    const only = Object.keys(approvers);
    if (only.length !== 1 || approvers.users === undefined) {
      throw new TypeError(
        `${where}.required "all" needs approvers.users and nothing else`,
      );
    }
    return { approvers, required: approvers.users.length };
  }
  if (
    typeof required !== "number" ||
    !Number.isInteger(required) ||
    required < 1
  ) {
    throw new TypeError(`${where}.required must be a whole number or "all"`);
  }
  if (
    approvers.users !== undefined &&
    Object.keys(approvers).length === 1 &&
    required > approvers.users.length
  ) {
    throw new TypeError(`${where}.required is more than approvers.users`);
  }
  return { approvers, required };
}

function runOf(value: unknown, where: string): ApprovalRun | undefined {
  if (value === undefined) return undefined;
  if (isFields(value) && typeof value["transition"] === "string") {
    return { kind: "transition", to: value["transition"] };
  }
  if (
    isFields(value) &&
    typeof value["queue"] === "string" &&
    KEY.test(value["queue"])
  ) {
    return { kind: "queue", queue: value["queue"] };
  }
  throw new TypeError(
    `${where}.run must be { transition: "<status>" } or { queue: "<queue>" }`,
  );
}

/** One policy; `where` names it in errors. */
export function policyOf(
  subjectType: string,
  action: string,
  value: unknown,
  where = `${WHERE}.${subjectType}.${action}`,
): ApprovalPolicy {
  if (!KEY.test(action)) throw new TypeError(`${where} has an invalid name`);
  if (!isFields(value)) throw new TypeError(`${where} must be an object`);
  const steps = value["steps"];
  if (!Array.isArray(steps) || steps.length === 0) {
    throw new TypeError(`${where}.steps must be a non-empty list`);
  }
  const expiresIn = value["expiresIn"];
  if (
    expiresIn !== undefined &&
    (typeof expiresIn !== "string" || !DURATION.test(expiresIn))
  ) {
    throw new TypeError(
      `${where}.expiresIn must be an ISO 8601 duration such as P7D`,
    );
  }
  const selfApproval = value["selfApproval"] ?? false;
  if (typeof selfApproval !== "boolean") {
    throw new TypeError(`${where}.selfApproval must be a boolean`);
  }
  const run = runOf(value["run"], where);
  return {
    subjectType,
    action,
    steps: steps.map((step: unknown, index) =>
      stepOf(step, `${where}.steps.${String(index)}`),
    ),
    selfApproval,
    ...(typeof expiresIn === "string" ? { expiresIn } : {}),
    ...(run === undefined ? {} : { run }),
  };
}

/** `options.policies`: subject type, then action, then the policy. */
export function approvalPolicies(
  ctx: ModuleContext,
): readonly ApprovalPolicy[] {
  const raw = ctx.option("policies");
  if (raw === undefined) return [];
  if (!isFields(raw)) throw new TypeError(`${WHERE} must be an object`);
  return Object.entries(raw).flatMap(([subjectType, actions]) => {
    if (!KEY.test(subjectType)) {
      throw new TypeError(`${WHERE}.${subjectType} has an invalid name`);
    }
    if (!isFields(actions)) {
      throw new TypeError(
        `${WHERE}.${subjectType} must be an object of action to policy`,
      );
    }
    return Object.entries(actions).map(([action, value]) =>
      policyOf(subjectType, action, value),
    );
  });
}

/** The snapshot a request stores, so later config changes leave it alone. */
export function policySnapshot(policy: ApprovalPolicy): string {
  return JSON.stringify({
    steps: policy.steps,
    selfApproval: policy.selfApproval,
    expiresIn: policy.expiresIn ?? null,
    run: policy.run ?? null,
  });
}
