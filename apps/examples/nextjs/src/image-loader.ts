import { createImageLoader } from "better-supabase/next/image";

import { env } from "@/env";

/**
 * Public Storage objects are resized by Supabase, not the Next.js optimizer.
 * Signed logo URLs pass through: they're signed at the rendered size.
 */
export default createImageLoader({ url: env.NEXT_PUBLIC_SUPABASE_URL });
