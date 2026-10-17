import type { DbError } from "better-supabase";

import { generatedOptions, rpcTransport } from "better-supabase/blocks";
import { createOrganizations } from "better-supabase/blocks/organizations";
import { tenantOf, useAuth, useSupabase } from "better-supabase/react";
import { useCallback, useMemo, useState } from "react";

import { blockConfig } from "@/lib/supabase/blocks.generated";

export interface CurrentOrganization {
  /** The active organization from the session's tenant claim. */
  readonly organizationId: string | undefined;
  readonly switching: boolean;
  readonly error: DbError | undefined;
  /** Makes another organization active, then refreshes the session when its claim changed. */
  readonly switchTo: (organizationId: string) => Promise<void>;
}

/**
 * The signed-in user's active organization, and a way to switch it. Works
 * in React DOM and React Native: it reads the session from `useAuth()` and
 * calls the organizations block as the user.
 */
export function useCurrentOrganization(): CurrentOrganization {
  const auth = useAuth();
  const supabase = useSupabase();

  const organizations = useMemo(
    () =>
      createOrganizations({
        ...generatedOptions(blockConfig.organizations),
        transport: rpcTransport(supabase),
      }),
    [supabase],
  );

  const [switching, setSwitching] = useState(false);
  const [error, setError] = useState<DbError | undefined>(undefined);

  const switchTo = useCallback(
    async (organizationId: string) => {
      setSwitching(true);
      const result = await organizations.switch(organizationId);

      if (result.ok) {
        setError(undefined);

        if (result.data.refresh) {
          await supabase.auth.refreshSession();
        }
      } else {
        setError(result.error);
      }

      setSwitching(false);
    },
    [organizations, supabase],
  );

  return { organizationId: tenantOf(auth), switching, error, switchTo };
}
