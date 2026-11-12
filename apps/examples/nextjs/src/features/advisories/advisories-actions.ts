"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { ADVISORIES_TAG } from "./advisories-cache";

const Id = v.pipe(v.string(), v.uuid());

const Text = (max: number) =>
  v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(max));

/** Adds a product the organization publishes advisories for. */
export const saveProduct = bsb.action(
  {
    input: v.object({
      key: v.pipe(v.string(), v.trim(), v.regex(/^[a-z0-9][a-z0-9_-]*$/)),
      name: Text(120),
      vendor: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(120))),
    }),
    requireTenant: true,
    permission: "advisories.write",
  },
  async ({ key, name, vendor }, { db, auth }) => {
    const saved = vendor
      ? await db.advisories.saveProduct({ key, name, vendor })
      : await db.advisories.saveProduct({ key, name });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, [ADVISORIES_TAG]);

    return ok(saved.data.id);
  },
);

/** Tracks a vulnerability by its CVE, GHSA or OSV id. */
export const trackVulnerability = bsb.action(
  {
    input: v.object({
      vulnId: Text(60),
      summary: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(500))),
    }),
    requireTenant: true,
    permission: "advisories.write",
  },
  async ({ vulnId, summary }, { db, auth }) => {
    const saved = summary
      ? await db.advisories.saveVulnerability({ vulnId, summary })
      : await db.advisories.saveVulnerability({ vulnId });

    if (!saved.ok) {
      return saved;
    }

    await refreshCaller(auth, [ADVISORIES_TAG]);

    return ok(saved.data.id);
  },
);

/** Publishes a draft advisory as a final CSAF document. */
export const publishAdvisory = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "advisories.publish",
  },
  async ({ id }, { db, auth }) => {
    const published = await db.advisories.publishAdvisory({
      id,
      status: "final",
    });

    if (!published.ok) {
      return published;
    }

    await refreshCaller(auth, [ADVISORIES_TAG]);

    return ok(published.data.id);
  },
);
