import 'server-only';

import { createNext } from 'better-supabase/next';

import { betterSupabase } from './index';

export const bsb = createNext(betterSupabase);
