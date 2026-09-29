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
    organizations: ['select'],
  },
  readSets: ['src/lib/read-sets.ts'],
  sql: { kit: ['read-sets'] },
});
