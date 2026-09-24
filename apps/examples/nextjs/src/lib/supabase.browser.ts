import { createBrowser } from 'better-supabase/client';

import { sb } from './supabase';

export const browser = createBrowser(sb, {
  env: {
    url: process.env.NEXT_PUBLIC_SUPABASE_URL!,
    publishableKey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  },
});
