"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

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
    requireOrganization: true,
    authorize: (session) => can(session, "templates.manage"),
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

    refreshCaller(auth);

    return ok({ id: saved.data.id, name: saved.data.name });
  },
);

/** Creates a customer from the template's newest published version. */
export const applyTemplate = bsb.action(
  {
    input: v.object({ templateId: v.pipe(v.string(), v.uuid()), name: Name }),
    requireOrganization: true,
    authorize: (session) =>
      can(session, "templates.apply") && can(session, "customers.write"),
  },
  async ({ templateId, name }, { tenant, supabase, db, auth }) => {
    const applied = await customerTemplates(supabase, (row) =>
      db.customers.create(row, { select: ["id"] }),
    ).apply(templateId, { into: tenant, values: { name } });

    if (!applied.ok) {
      return applied;
    }

    refreshCaller(auth);

    return ok({ customerId: applied.data.subject.id });
  },
);
