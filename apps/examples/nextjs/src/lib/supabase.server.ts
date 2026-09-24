import { createNext } from 'better-supabase/next';

import { sb } from './supabase';

export const next = createNext(sb);
