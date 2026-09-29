import { defineSupabase } from 'better-supabase';

import { schema } from './supabase/generated.ts';

export type { Functions, Models } from './supabase/generated.ts';

export const sb = defineSupabase(schema);
