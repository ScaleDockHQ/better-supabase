import { defineSupabase } from 'better-supabase';

import { schema } from '../../../lib/supabase/generated.ts';

export const sb = defineSupabase(schema);
