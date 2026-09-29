import { defineSupabase } from 'better-supabase';

import { Claims } from './claims.ts';
import { schema } from './supabase/generated.ts';

export type { Functions, Models } from './supabase/generated.ts';

export const sb = defineSupabase(schema).claims(Claims);
