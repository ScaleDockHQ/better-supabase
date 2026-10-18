/** The subject type the request form files approvals for. */
export const APPROVAL_SUBJECT = "customer";

/** The actions the customer approval policy names. */
export const APPROVAL_ACTIONS = ["discount"] as const;

export type ApprovalAction = (typeof APPROVAL_ACTIONS)[number];

/** A request as the client components get it: plain JSON, no Temporal. */
export interface ApprovalRow {
  readonly id: string;
  readonly subjectType: string;
  readonly subjectId: string;
  /** The customer's name, when the subject is a customer the caller can read. */
  readonly subjectName: string | null;
  readonly action: string;
  readonly step: number;
  readonly steps: number;
  readonly requestedBy: string | null;
  readonly reason: string | null;
  readonly createdAt: string;
}

export interface SubjectOption {
  readonly id: string;
  readonly name: string;
}
