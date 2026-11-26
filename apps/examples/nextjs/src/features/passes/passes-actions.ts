"use server";

import type { PassInput } from "better-supabase/blocks/passes";

import { ok } from "better-supabase";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

const Id = v.pipe(v.string(), v.uuid());

/** Issues a pass to a named holder, with an optional number of uses. */
export const issuePass = bsb.action(
  {
    input: v.object({
      holderName: v.pipe(
        v.string(),
        v.trim(),
        v.minLength(1),
        v.maxLength(120),
      ),
      holderEmail: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(200))),
      kind: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(60))),
      usesAllowed: v.optional(
        v.pipe(
          v.string(),
          v.trim(),
          v.transform((value) => (value === "" ? undefined : Number(value))),
          v.optional(
            v.pipe(v.number(), v.integer(), v.minValue(1), v.maxValue(1000)),
          ),
        ),
      ),
    }),
    requireTenant: true,
    permission: "passes.manage",
    tags: () => [tags.passes()],
    refresh: true,
  },
  async ({ holderName, holderEmail, kind, usesAllowed }, { db }) => {
    const input: Mutable<PassInput> = { holderName };

    if (holderEmail) {
      input.holderEmail = holderEmail;
    }

    if (kind) {
      input.kind = kind;
    }

    if (usesAllowed !== undefined) {
      input.usesAllowed = usesAllowed;
    }

    const issued = await db.passes.issue(input);

    if (!issued.ok) {
      return issued;
    }

    return ok(issued.data.id);
  },
);

/** Revokes a pass; later scans are turned away. */
export const revokePass = bsb.action(
  {
    input: v.object({ passId: Id }),
    requireTenant: true,
    permission: "passes.manage",
    tags: () => [tags.passes()],
    refresh: true,
  },
  async ({ passId }, { db }) => {
    const revoked = await db.passes.revoke(passId);

    if (!revoked.ok) {
      return revoked;
    }

    return ok(revoked.data.id);
  },
);

/** Checks a holder in by pass id, for staff at the door. */
export const checkInPass = bsb.action(
  {
    input: v.object({ passId: Id }),
    requireTenant: true,
    permission: "passes.check_in",
    tags: () => [tags.passes()],
    refresh: true,
  },
  async ({ passId }, { db }) => {
    const scanned = await db.passes.checkInManually({ passId });

    if (!scanned.ok) {
      return scanned;
    }

    return ok(scanned.data.admitted);
  },
);
