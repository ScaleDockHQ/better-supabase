'use server';

import { dbError, err } from 'better-supabase';
import { z } from 'zod';

import { next } from '@/lib/supabase.server';

/** Sends the caller a notification; the header badge updates over Realtime. */
export const notifyMe = next.action(
  { input: z.object({ title: z.string().min(1).max(200) }) },
  async ({ title }, { auth, db }) => {
    const organizationId =
      auth.kind === 'user' ? auth.claims.app_metadata?.org_id : undefined;
    if (!organizationId) {
      return err(dbError('forbidden', 'Your account has no organization'));
    }
    return db.notifications.create(
      { organizationId, title },
      { select: ['id'] },
    );
  },
);

export const markAllRead = next.action({}, async (_input, { db }) =>
  db.notifications.updateMany({
    where: { readAt: null },
    data: { readAt: new Date().toISOString() },
  }),
);
