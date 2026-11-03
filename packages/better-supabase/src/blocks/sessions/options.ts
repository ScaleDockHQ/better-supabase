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
   * the check skips its own subject query). Renders
   * `better_supabase.bootstrap_<name>`.
   */
  readonly bootstrap?: Readonly<
    Record<
      string,
      | string
      | { readonly readSet: string; readonly subject?: string }
      | {
          readonly readSets: readonly string[];
          readonly shell?: string;
          readonly subject?: string;
        }
    >
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
