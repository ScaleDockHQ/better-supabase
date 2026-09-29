import { defineSupabase } from 'better-supabase';

import { toAppError } from './app-error.ts';
import { Claims } from './claims.ts';
import { schema } from './supabase/generated.ts';

export type { Functions, Models } from './supabase/generated.ts';

/** `.orThrow()` throws an `AppError`; results keep their `DbError`. */
export const sb = defineSupabase(schema).claims(Claims).mapError(toAppError);
