import type { RequestContext } from "../core/plugin.ts";
import type { AuthState } from "./resolve.ts";

import { userContext } from "./impersonation.ts";

/** The repository context (`actor`, `claims`) for an auth state. */
export function authContext(auth: AuthState): RequestContext {
  switch (auth.kind) {
    case "user": {
      return userContext(auth.user, auth.claims);
    }

    case "secret": {
      return {
        actor: {
          id: `service:${auth.keyName}`,
          kind: "service",
          role: "service_role",
        },
        claims: { role: "service_role" },
      };
    }

    case "apiKey": {
      return {
        actor: auth.userId
          ? { id: auth.userId, kind: "user", role: "authenticated" }
          : {
              id: `api-key:${auth.keyId}`,
              kind: "service",
              role: "authenticated",
            },
        claims: auth.claims,
        ...(auth.organizationId ? { tenant: auth.organizationId } : {}),
      };
    }

    case "none":
    case "invalid": {
      return {
        actor: { id: "anon", kind: "anon", role: "anon" },
        claims: { role: "anon" },
      };
    }

    default: {
      const exhaustive: never = auth;

      return exhaustive;
    }
  }
}
