import "server-only";
import { tenantOf } from "better-supabase/next";
import { unstable_rethrow } from "next/navigation";

import { getMembers } from "@/features/organization/organization-queries";
import { bsb } from "@/lib/supabase/server";

import type { ApprovalRow, SubjectOption } from "./approvals-types";

import { APPROVAL_SUBJECT } from "./approvals-types";

export interface ApprovalsQueue {
  readonly requests: readonly ApprovalRow[];
  readonly customers: readonly SubjectOption[];
}

export type Loaded<T> =
  | { readonly kind: "ok"; readonly data: T }
  | { readonly kind: "no-organization" }
  | { readonly kind: "error" };

/**
 * The pending requests, newest first, with the customers a new request can
 * name. Throws on a failed read, so the private cache never keeps an error.
 */
async function loadQueue(): Promise<ApprovalsQueue | null> {
  "use cache: private";
  const { session, db } = await bsb.cached();
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const [requests, customers, members] = await Promise.all([
    db.approvals.list({ status: "pending", pageSize: 100 }).orThrow(),
    db.customers
      .list({ select: ["id", "name"], orderBy: { name: "asc" }, limit: 200 })
      .orThrow(),
    getMembers(tenant),
  ]);

  const customerNames = new Map(
    customers.map((customer) => [customer.id, customer.name]),
  );

  const memberNames = new Map(
    members.map((member) => [
      member.userId,
      member.name ?? member.email ?? member.userId,
    ]),
  );

  return {
    requests: requests.map((request) => ({
      id: request.id,
      subjectType: request.subject.type,
      subjectId: request.subject.id,
      subjectName:
        request.subject.type === APPROVAL_SUBJECT
          ? (customerNames.get(request.subject.id) ?? null)
          : null,
      action: request.action,
      step: request.step,
      steps: request.steps.length,
      requestedBy:
        request.requestedBy === undefined
          ? null
          : (memberNames.get(request.requestedBy) ?? null),
      reason: request.reason ?? null,
      createdAt: request.createdAt.toString(),
    })),
    customers: customers.map((customer) => ({
      id: customer.id,
      name: customer.name,
    })),
  };
}

export async function getApprovalsQueue(): Promise<Loaded<ApprovalsQueue>> {
  try {
    const data = await loadQueue();

    return data === null ? { kind: "no-organization" } : { kind: "ok", data };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
