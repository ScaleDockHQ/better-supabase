/**
 * A run queued before its engine run exists: `externalId` starts with
 * `pending:` and `claimForDispatch` leases it. It lives apart from the
 * workflows block so `better-supabase/workflow-sdk` does not bundle the block.
 */
export const PENDING_RUN_PREFIX = "pending:";
