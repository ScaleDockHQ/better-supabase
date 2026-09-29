import { defineConfig } from 'better-supabase/config';

const crud = ['select', 'insert', 'update', 'delete'] as const;

export default defineConfig({
  source: {
    snapshot: '../../../supabase/snapshot.json',
    // The repo's `supabase start` stack, for `doctor --explain` and `--stats`.
    dbUrl: 'postgresql://postgres:postgres@127.0.0.1:55422/postgres',
  },
  casing: 'camel',
  output: 'src/lib/supabase/generated.ts',
  expose: {
    customers: crud,
    contacts: crud,
    locations: crud,
    notes: crud,
    tags: crud,
    customer_tags: crud,
    notifications: crud,
    organizations: ['select'],
  },
  // Topics per organization: `bs:t:public.notifications:<org id>`.
  plugins: { tenant: { column: 'organization_id' } },
  realtime: { tables: ['notifications'] },
  buckets: {
    customerLogos: {
      path: '{orgId}/{customerId}/logo/{version}.webp',
      public: true,
      policy: 'tenant',
      fileSizeLimit: '5MiB',
      allowedMimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
    },
  },
  // Rows store the object path; URLs are built when rendering.
  storagePaths: { 'customers.logo_path': 'customerLogos' },
  readSets: ['src/lib/read-sets.ts'],
  sql: { kit: ['read-sets', 'realtime-tables', 'rate-limit'] },
});
