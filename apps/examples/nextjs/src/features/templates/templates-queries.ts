import "server-only";
import type { TemplateScope } from "better-supabase/blocks/templates";

import { tenantOf } from "better-supabase/next";
import { cacheTag } from "next/cache";
import { unstable_rethrow } from "next/navigation";
import * as v from "valibot";

import { bsb } from "@/lib/supabase/server";

import { TEMPLATES_TAG } from "./templates-cache";
import { CustomerTemplateBody, templatesOf } from "./templates-server";

export interface TemplateCard {
  readonly id: string;
  readonly name: string;
  readonly scope: TemplateScope;
  readonly isDefault: boolean;
  /** `null` before the first publish, when the template can't be applied. */
  readonly publishedVersion: number | null;
  /** The published body's status, or `null` when the body doesn't parse. */
  readonly status: CustomerTemplateBody["status"] | null;
  /** ISO 8601, so the cached value stays serializable. */
  readonly updatedAt: string;
}

export type TemplatesView =
  | { readonly kind: "ok"; readonly templates: readonly TemplateCard[] }
  | { readonly kind: "error" }
  | { readonly kind: "no-organization" };

/** A failed read throws, so it is never cached and Retry reads again. */
async function loadTemplates(): Promise<readonly TemplateCard[] | null> {
  "use cache: private";
  const { session, supabase } = await bsb.cached();
  cacheTag(TEMPLATES_TAG);
  const tenant = tenantOf(session);

  if (!tenant) {
    return null;
  }

  const templates = templatesOf(supabase);

  const list = await templates
    .list({ organizationId: tenant, filter: { type: "customer", limit: 100 } })
    .orThrow();

  const details = new Map(
    (
      await templates.getMany(list.map((template) => template.id)).orThrow()
    ).map((detail) => [detail.id, detail]),
  );

  return list.map((template) => {
    const body = v.safeParse(
      CustomerTemplateBody,
      details.get(template.id)?.published?.body,
    );

    return {
      id: template.id,
      name: template.name,
      scope: template.scope,
      isDefault: template.isDefault,
      publishedVersion: template.publishedVersion ?? null,
      status: body.success ? body.output.status : null,
      updatedAt: template.updatedAt.toString(),
    };
  });
}

export async function getTemplates(): Promise<TemplatesView> {
  try {
    const templates = await loadTemplates();

    return templates === null
      ? { kind: "no-organization" }
      : { kind: "ok", templates };
  } catch (error) {
    unstable_rethrow(error);

    return { kind: "error" };
  }
}
