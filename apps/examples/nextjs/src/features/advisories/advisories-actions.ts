"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { tags } from "@/lib/supabase/generated.tags";
import { bsb } from "@/lib/supabase/server";

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
    tags: () => [tags.advisories()],
    refresh: true,
  },
  async ({ key, name, vendor }, { db }) => {
    const saved = vendor
      ? await db.advisories.saveProduct({ key, name, vendor })
      : await db.advisories.saveProduct({ key, name });

    if (!saved.ok) {
      return saved;
    }

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
    tags: () => [tags.advisories()],
    refresh: true,
  },
  async ({ vulnId, summary }, { db }) => {
    const saved = summary
      ? await db.advisories.saveVulnerability({ vulnId, summary })
      : await db.advisories.saveVulnerability({ vulnId });

    if (!saved.ok) {
      return saved;
    }

    return ok(saved.data.id);
  },
);

/** Publishes a draft advisory as a final CSAF document. */
export const publishAdvisory = bsb.action(
  {
    input: v.object({ id: Id }),
    requireTenant: true,
    permission: "advisories.publish",
    tags: () => [tags.advisories()],
    refresh: true,
  },
  async ({ id }, { db }) => {
    const published = await db.advisories.publishAdvisory({
      id,
      status: "final",
    });

    if (!published.ok) {
      return published;
    }

    return ok(published.data.id);
  },
);
