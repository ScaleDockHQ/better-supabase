'use server';

import { dbError, err } from 'better-supabase';
import { toSession } from 'better-supabase/next';
import { z } from 'zod';

import { can } from '@/features/user/user-permissions';
import { next } from '@/lib/supabase.server';

/** Mutations invalidate `bs:customers` with `updateTag` (see `createNext`). */
export const createCustomer = next.action(
  { input: z.object({ name: z.string().min(1).max(200) }) },
  async ({ name }, { auth, db }) => {
    if (!can(toSession(auth), 'customers.write')) {
      return err(dbError('forbidden', 'You cannot add customers'));
    }
    const organizationId =
      auth.kind === 'user' ? auth.claims.app_metadata?.['org_id'] : undefined;
    if (typeof organizationId !== 'string') {
      return err(dbError('forbidden', 'Your account has no organization'));
    }
    return db.customers.create(
      { name, organizationId },
      { select: ['id', 'name', 'status'] },
    );
  },
);
