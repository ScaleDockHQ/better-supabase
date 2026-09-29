import { defineReadSet, defineSupabase } from 'better-supabase';
import { defineListQuery } from 'better-supabase/list';
import { tenant } from 'better-supabase/plugins/tenant';
import { z } from 'zod';

import { schema } from './generated.ts';

export const sb = defineSupabase(schema);

/**
 * The customers overview: the page, the per-status counts and each
 * row's contact count and latest update of a location, in two requests
 * that run in parallel. The original service ran up to six sequential queries.
 */
export const customerOverview = defineListQuery(sb, 'customers', {
  search: ['companyName', 'sortName', 'billingEmail'],
  facets: { status: 'status', business: 'isBusiness' },
  sorts: {
    name: [{ sortName: 'asc' }, { id: 'asc' }],
    updated: [{ updatedAt: 'desc' }, { id: 'asc' }],
  },
  defaultSort: 'name',
  pageSize: 25,
  facetCounts: true,
});

/**
 * The three badges in the app chrome (unread notifications, my open
 * tasks, approvals waiting on me) as one read set: `gen` compiles it into
 * `public.rs_app_chrome(p jsonb)`, and `db.$many` calls it with one GET.
 */
export const appChrome = defineReadSet(
  sb,
  'app_chrome',
  { params: { userId: 'uuid' } },
  (s, p) => ({
    unread: s.notificationRecipients.count({
      where: { recipientUserId: p.userId, readAt: null, dismissedAt: null },
    }),
    openTasks: s.tasks.count({
      where: {
        status: { in: ['todo', 'in_progress'] },
        taskAssignees: { some: { userId: p.userId } },
      },
    }),
    approvals: s.approvalRequests.count({
      where: { status: 'requested', approverUserId: p.userId },
    }),
  }),
);

/** Claims of the customer portal token: the customer it may see. */
export const PortalClaims = z.object({
  sub: z.uuid(),
  customer_id: z.string().regex(/^\d+$/),
});

/**
 * The portal generates with `plugins.tenant.column: 'customer_id'`; this
 * marks the same tables on the staff schema, so one snapshot serves both.
 */
const portalMeta = {
  ...schema.meta,
  tables: Object.fromEntries(
    Object.entries(schema.meta.tables).map(([key, table]) => [
      key,
      table.columns['customerId']
        ? { ...table, flags: { ...table.flags, tenant: 'customerId' } }
        : table,
    ]),
  ),
};

export const portal = defineSupabase({ ...schema, meta: portalMeta })
  .claims(PortalClaims)
  .use(tenant<z.output<typeof PortalClaims>>({ claim: 'customer_id' }));
