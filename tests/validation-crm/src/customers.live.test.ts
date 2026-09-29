import { createClient } from '@supabase/supabase-js';
import { defineSupabase } from 'better-supabase';
import { describe, expect, it } from 'vitest';

import { createCustomersService } from './customers.ts';
import { schema } from './generated.ts';

const url = process.env['CRM_SUPABASE_URL'];
const secretKey = process.env['CRM_SUPABASE_SECRET_KEY'];

describe.skipIf(!url || !secretKey)(
  'CRM customers against a running CRM stack (read-only)',
  () => {
    it('runs the overview query with every filter and include', async () => {
      const db = defineSupabase(schema).connect(
        createClient(url!, secretKey!, { auth: { persistSession: false } }),
      );
      const customers = createCustomersService(db);

      const organization = await db.organizations
        .findFirst({ select: ['id'] })
        .orThrow();
      if (!organization) return;
      for (const filter of [
        {},
        { q: 'a', types: ['business'] as const, sortBy: 'updatedAt' as const },
        {
          assigneeIds: ['00000000-0000-4000-8000-000000000000'],
          unassigned: true,
        },
        {
          tagIds: ['00000000-0000-4000-8000-000000000000'],
          statuses: ['active', 'prospect'] as const,
        },
      ]) {
        const result = await customers.listCustomers(organization.id, filter);
        expect(result).toMatchObject({ ok: true });
      }
      const page = await customers
        .listCustomers(organization.id, { size: 5 })
        .orThrow();
      for (const row of page.items) {
        expect(Array.isArray(row.customerTags)).toBe(true);
        expect(row.customerContacts.length).toBeLessThanOrEqual(1);
      }
      const first = page.items[0];
      const detail = first
        ? await customers.getCustomer(organization.id, first.id).orThrow()
        : undefined;
      expect(detail?.id).toBe(first?.id);
    });
  },
);
