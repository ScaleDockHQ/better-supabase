'use server';

import { dbError, err } from 'better-supabase';
import { z } from 'zod';

import { next } from '../lib/supabase.server';

export const createCustomer = next.action(
  { input: z.object({ name: z.string().min(1).max(200) }) },
  async ({ name }, { auth, db }) => {
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
