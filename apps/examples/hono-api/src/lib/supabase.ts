import { defineSupabase } from 'better-supabase';

import { schema } from './supabase/generated';

export type { Functions, Models } from './supabase/generated';

export const sb = defineSupabase(schema);
