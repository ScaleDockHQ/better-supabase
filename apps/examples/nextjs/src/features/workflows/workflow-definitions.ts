import type { RequestContext } from "better-supabase";

import { createHook, getWorkflowMetadata, sleep } from "workflow";

import {
  type DocumentSummary,
  notifyActor,
  summarizeDocument,
} from "./workflow-steps";

/** A welcome now and a tip a minute later (a day, in a real drip). */
export async function onboardingDrip(context: RequestContext): Promise<void> {
  "use workflow";
  await notifyActor(context, "Welcome to Acme");
  await sleep("1 minute");
  await notifyActor(context, "Tip: invite your team from Settings");
}

/** Parses a document, then tells the actor it is ready. */
export async function documentIngestion(
  context: RequestContext,
  text: string,
): Promise<DocumentSummary> {
  "use workflow";
  const summary = await summarizeDocument(text);
  await notifyActor(
    context,
    `Document ingested: ${summary.words} words, ${summary.sentences} sentences`,
  );
  return summary;
}

export interface ApprovalDecision {
  readonly approved: boolean;
  readonly by: string;
}

/** The hook token of an expense approval run, which the UI rebuilds from the run id. */
export function approvalToken(runId: string): string {
  return `expense-approval:${runId}`;
}

/**
 * Waits for an approval. `metadata` is `hookMetadata(context,
 * "workflow.admin")`, so `authorizeHook` lets the requester or an admin of
 * the tenant decide, never a caller who only has the token.
 */
export async function expenseApproval(
  context: RequestContext,
  amount: number,
  metadata: Readonly<Record<string, string>>,
): Promise<ApprovalDecision> {
  "use workflow";
  const { workflowRunId } = getWorkflowMetadata();
  const hook = createHook<ApprovalDecision>({
    token: approvalToken(workflowRunId),
    metadata,
  });
  const decision = await hook;
  await notifyActor(
    context,
    decision.approved
      ? `Expense of ${amount} approved`
      : `Expense of ${amount} rejected`,
  );
  return decision;
}

/** The workflows schedules and admission may start, by the name they store. */
export const scheduledWorkflows = {
  "onboarding-drip": onboardingDrip,
  "document-ingestion": documentIngestion,
};
