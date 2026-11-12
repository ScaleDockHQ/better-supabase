"use server";

import type { Result } from "better-supabase";

import { dbError, err, ok } from "better-supabase";
import * as v from "valibot";

import { requireCaller, sqlResult } from "@/features/developer/postgres";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { OPTION_SETS_TAG } from "./option-sets-cache";

const Id = v.pipe(v.string(), v.uuid());

const manage = {
  requireTenant: true,
  permission: "option_sets.manage",
} as const;

/**
 * Creates the default set of a field from its binding (`ensure_option_set`), so
 * calling it again is safe. The tasks block binds `work_item.priority`.
 */
export const ensureOptionSet = bsb.action(
  {
    ...manage,
    input: v.object({
      subjectType: v.pipe(v.string(), v.maxLength(63)),
      field: v.pipe(v.string(), v.maxLength(63)),
    }),
  },
  async (
    { subjectType, field },
    { tenant, session, auth },
  ): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const ensured = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw("select better_supabase.ensure_option_set($1, $2, $3)", [
          tenant,
          subjectType,
          field,
        ]),
    );

    if (!ensured.ok) {
      return ensured;
    }

    await refreshCaller(auth, [OPTION_SETS_TAG]);

    return ok(true);
  },
);

/** Renames an item and changes its color; the key and level stay. */
export const editOptionItem = bsb.action(
  {
    ...manage,
    input: v.object({
      setId: Id,
      itemId: Id,
      label: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200)),
      color: v.pipe(v.string(), v.trim(), v.maxLength(50)),
    }),
  },
  async (
    { setId, itemId, label, color },
    { tenant, session, auth },
  ): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const saved = await sqlResult(async () => {
      const sql = connection.asUser(claims);

      const [item] = await sql.queryRaw<{
        key: string;
        level: number;
        icon: string | null;
        description: string | null;
      }>(
        `select key, level, icon, description from better_supabase.option_set_items
         where id = $1 and option_set_id = $2 and tenant_id = $3`,
        [itemId, setId, tenant],
      );

      if (!item) {
        return false;
      }

      await sql.queryRaw(
        "select better_supabase.save_option_set_item($1, $2, $3, $4, $5, $6, $7, $8)",
        [
          setId,
          itemId,
          item.key,
          label,
          item.level,
          color === "" ? null : color,
          item.icon,
          item.description,
        ],
      );

      return true;
    });

    if (!saved.ok) {
      return saved;
    }

    if (!saved.data) {
      return err(dbError("not_found", "Option not found"));
    }

    await refreshCaller(auth, [OPTION_SETS_TAG]);

    return ok(true);
  },
);

/** Archives an item; one that records still use needs a replacement first. */
export const archiveOptionItem = bsb.action(
  { ...manage, input: v.object({ itemId: Id }) },
  async ({ itemId }, { session, auth }): Promise<Result<boolean>> => {
    const caller = requireCaller(session);

    if (!caller.ok) {
      return caller;
    }

    const { connection, claims } = caller.data;

    const archived = await sqlResult(() =>
      connection
        .asUser(claims)
        .queryRaw("select better_supabase.archive_option_set_item($1, null)", [
          itemId,
        ]),
    );

    if (!archived.ok) {
      return archived;
    }

    await refreshCaller(auth, [OPTION_SETS_TAG]);

    return ok(true);
  },
);
