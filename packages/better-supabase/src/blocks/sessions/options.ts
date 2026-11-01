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
   * Wrapper name to `schema.function`, or to `{ readSet: "name" }` for the read
   * set `defineReadSet(db, "name", ...)` installs as `public.rs_name`; renders
   * `better_supabase.bootstrap_<name>`.
   */
  readonly bootstrap?: Readonly<
    Record<string, string | { readonly readSet: string }>
  >;
  readonly exclude?: readonly string[];
  readonly policies?: boolean;
};

export const sessionsSqlOptions: BlockOptionsSchema<SessionsSqlOptions> =
  blockOptions<SessionsSqlOptions>({
    authzVersions: option.boolean({ default: false }),
    bootstrap: option.unknown<NonNullable<SessionsSqlOptions["bootstrap"]>>(),
    exclude: option.strings({ default: [] }),
    policies: option.boolean({ default: false }),
  });
