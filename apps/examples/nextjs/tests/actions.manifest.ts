/**
 * The Server Actions `actions.spec.ts` calls, with the page they belong to and
 * the arguments of one call. An action of the build that is not listed here
 * counts as uncovered in `perf/report.json`. `mutates` marks a write, which the
 * spec runs after the reads so a write cannot change what a read measures.
 */

export interface ActionCase {
  /** The action file under src/, for instance `features/inbox/inbox-actions.ts`. */
  readonly file: string;
  readonly name: string;
  /** The page whose UI calls the action. */
  readonly page: string;
  readonly args: readonly unknown[];
  readonly mutates: boolean;
}

const read = (
  file: string,
  name: string,
  page: string,
  args: readonly unknown[] = [],
): ActionCase => ({ file, name, page, args, mutates: false });

export const ACTIONS: readonly ActionCase[] = [
  read(
    "features/organization/organization-actions.ts",
    "loadMyOrganizations",
    "/",
  ),
  read("features/organization/organization-actions.ts", "loadMembers", "/settings/members"),
  read("features/billing/billing-actions.ts", "loadPlanCatalog", "/settings/billing"),
  read("features/inbox/inbox-actions.ts", "loadInboxes", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadTeams", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadMacros", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadDrafts", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadScheduled", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadInboundEvents", "/inbox"),
  read("features/inbox/inbox-actions.ts", "loadConversations", "/inbox"),
  read("features/knowledge/knowledge-actions.ts", "searchKnowledge", "/knowledge", [
    { query: "refund" },
  ]),
];
