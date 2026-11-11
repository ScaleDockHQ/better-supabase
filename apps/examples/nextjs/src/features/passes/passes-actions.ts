"use server";

import type { PassInput } from "better-supabase/blocks/passes";

import { ok } from "better-supabase";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { PASSES_TAG } from "./passes-cache";

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
  },
  async ({ holderName, holderEmail, kind, usesAllowed }, { db, auth }) => {
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

    await refreshCaller(auth, [PASSES_TAG]);

    return ok(issued.data.id);
  },
);

/** Revokes a pass; later scans are turned away. */
export const revokePass = bsb.action(
  {
    input: v.object({ passId: Id }),
    requireTenant: true,
    permission: "passes.manage",
  },
  async ({ passId }, { db, auth }) => {
    const revoked = await db.passes.revoke(passId);

    if (!revoked.ok) {
      return revoked;
    }

    await refreshCaller(auth, [PASSES_TAG]);

    return ok(revoked.data.id);
  },
);

/** Checks a holder in by pass id, for staff at the door. */
export const checkInPass = bsb.action(
  {
    input: v.object({ passId: Id }),
    requireTenant: true,
    permission: "passes.check_in",
  },
  async ({ passId }, { db, auth }) => {
    const scanned = await db.passes.checkInManually({ passId });

    if (!scanned.ok) {
      return scanned;
    }

    await refreshCaller(auth, [PASSES_TAG]);

    return ok(scanned.data.admitted);
  },
);
