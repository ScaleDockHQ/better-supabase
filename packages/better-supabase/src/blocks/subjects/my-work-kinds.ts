/** What a `my_work` item waits on. */
export type MyWorkKind =
  | "assigned"
  | "approval"
  | "reminder"
  | "mention"
  | "sla";

/** The kinds `my_work` returns, in the order the docs list them. */
export const MY_WORK_KINDS: readonly MyWorkKind[] = [
  "assigned",
  "approval",
  "reminder",
  "mention",
  "sla",
];
