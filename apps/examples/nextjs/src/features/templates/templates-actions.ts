"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";
import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import {
  CustomerTemplateBody,
  customerTemplates,
  templatesOf,
} from "./templates-server";

const Name = v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(200));

/** Saves a customer template and publishes its first version. */
export const createTemplate = bsb.action(
  {
    input: v.object({ name: Name, ...CustomerTemplateBody.entries }),
    requireTenant: true,
    permission: "templates.manage",
  },
  async ({ name, status }, { tenant, supabase, auth }) => {
    const templates = templatesOf(supabase);

    const saved = await templates.upsert({
      organizationId: tenant,
      type: "customer",
      name,
    });

    if (!saved.ok) {
      return saved;
    }

    const draft = await templates.versions.upsert(saved.data.id, { status });

    if (!draft.ok) {
      return draft;
    }

    const published = await templates.versions.publish(saved.data.id);

    if (!published.ok) {
      return published;
    }

    await refreshCaller(auth);

    return ok({ id: saved.data.id, name: saved.data.name });
  },
);

/** Creates a customer from the template's newest published version. */
export const applyTemplate = bsb.action(
  {
    input: v.object({ templateId: v.pipe(v.string(), v.uuid()), name: Name }),
    requireTenant: true,
    permission: "templates.apply",
    authorize: async () => can(await getPermissions(), "customers.write"),
  },
  async ({ templateId, name }, { tenant, supabase, db, auth }) => {
    const applied = await customerTemplates(supabase, (row) =>
      db.customers.create(row, { select: ["id"] }),
    ).apply(templateId, { into: tenant, values: { name } });

    if (!applied.ok) {
      return applied;
    }

    await refreshCaller(auth);

    return ok({ customerId: applied.data.subject.id });
  },
);
