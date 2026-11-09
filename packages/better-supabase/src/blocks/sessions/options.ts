import type { BlockOptionsSchema } from "../options.ts";

import { blockOptions, option } from "../options.ts";

/** `blocks['sessions'].options`. */
export type SessionsSqlOptions = {
  /**
   * Renders `better_supabase.user_authz_versions`, its bump trigger and the
   * `authz:<uid>` broadcast that `SessionProvider` listens to.
   */
  readonly authzVersions?: boolean;
  /**
   * Wrapper name to `schema.function`, to `{ readSet: "name" }` for the read
   * set `defineReadSet(db, "name", ...)` installs as `public.rs_name`, or to `{
   * readSets, shell? }`: the caller picks one of the read sets per call with
   * `bsb.bootstrap({ rpc, readSet, params })`, and `shell` is an optional
   * function whose result is `data`. Either form takes `subject`, a no-argument
   * function whose jsonb result the authorizer reads (`accessFor` seeds it, so
   * the check skips its own subject query). Without it, an entry takes the
   * authorization provider's `functions.subject`; `subject: false` opts out.
   * String entries take the provider's too. `{ function, tables?, subject? }`
   * is the string form with options. Every object form takes `tables`, the
   * tables the payload reads (model keys): `bsb.bootstrap({ rpc })` tags its
   * cache entry with them, and without `tables` `gen` derives them from the
   * function body. Renders `better_supabase.bootstrap_<name>`. With the
   * provider's `functions.bootstrapPermissions` the wrapper also returns the
   * caller's permissions (`Bootstrap.permissions`); `permissions: false` on an
   * entry leaves them out.
   */
  readonly bootstrap?: Readonly<
    Record<
      string,
      | string
      | {
          readonly function: string;
          readonly tables?: readonly string[];
          readonly subject?: string | false;
          readonly permissions?: false;
        }
      | {
          readonly readSet: string;
          readonly tables?: readonly string[];
          readonly subject?: string | false;
          readonly permissions?: false;
        }
      | {
          readonly readSets: readonly string[];
          readonly shell?: string;
          readonly tables?: readonly string[];
          readonly subject?: string | false;
          readonly permissions?: false;
        }
    >
  >;
  readonly exclude?: readonly string[];
  /**
   * Renders `better_supabase.hook_plan(event)`, which the app's access token
   * hook calls first: `'slim'` for an OAuth client token (`oauth: 'slim'`),
   * `'reuse'` for a refresh whose `authz_ver` is still current (`refresh:
   * 'reuse'`, the default, which needs `authzVersions` or a provider with
   * `versions`), `'full'` otherwise. `true` takes the defaults;
   * `truncatedClaim` names the claim that marks a partial `permissions` and
   * `teamIdsTruncatedClaim` the one that marks a partial `team_ids`; both
   * default to the provider hook's claims, then `permissions_truncated` and
   * `team_ids_truncated`.
   */
  readonly hook?:
    | boolean
    | {
        readonly refresh?: "reuse" | "full";
        readonly oauth?: "full" | "slim";
        readonly truncatedClaim?: string;
        readonly teamIdsTruncatedClaim?: string;
      };
  readonly policies?: boolean;
};

export const sessionsSqlOptions: BlockOptionsSchema<SessionsSqlOptions> =
  blockOptions<SessionsSqlOptions>({
    authzVersions: option.boolean({ default: false }),
    bootstrap: option.unknown<NonNullable<SessionsSqlOptions["bootstrap"]>>(),
    exclude: option.strings({ default: [] }),
    hook: option.unknown<NonNullable<SessionsSqlOptions["hook"]>>(),
    policies: option.boolean({ default: false }),
  });
