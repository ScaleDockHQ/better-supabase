import { approvalWaiter } from "../../../src/workflow-sdk/approval-waiter.ts";

export async function waitForApproval(
  token: string,
): Promise<{ status: string }> {
  "use workflow";

  const result = await approvalWaiter.wait(token, {
    expiresAt: "2999-01-01T00:00:00Z",
  });

  return { status: result.status };
}
