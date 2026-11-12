"use server";

import { ok } from "better-supabase";
import * as v from "valibot";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { INCIDENTS_TAG } from "./incidents-cache";

const Id = v.pipe(v.string(), v.uuid());

const Text = (max: number) =>
  v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(max));

export const SEVERITIES = ["sev1", "sev2", "sev3", "sev4"] as const;

export const OPEN_STATUSES = [
  "investigating",
  "identified",
  "monitoring",
] as const;

/** Opens an incident with a first timeline entry. */
export const openIncident = bsb.action(
  {
    input: v.object({
      title: Text(200),
      severity: v.picklist(SEVERITIES),
      message: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(2000))),
    }),
    requireTenant: true,
    permission: "incidents.write",
  },
  async ({ title, severity, message }, { tenant, db, auth }) => {
    const opened = message
      ? await db.incidents.open({
          organizationId: tenant,
          input: { title, severity, message },
        })
      : await db.incidents.open({
          organizationId: tenant,
          input: { title, severity },
        });

    if (!opened.ok) {
      return opened;
    }

    await refreshCaller(auth, [INCIDENTS_TAG]);

    return ok(opened.data.id);
  },
);

/** Posts a status update to an open incident's timeline. */
export const postIncidentUpdate = bsb.action(
  {
    input: v.object({
      incidentId: Id,
      status: v.picklist(OPEN_STATUSES),
      body: Text(2000),
    }),
    requireTenant: true,
    permission: "incidents.write",
  },
  async ({ incidentId, status, body }, { db, auth }) => {
    const posted = await db.incidents.postUpdate({
      incidentId,
      input: { status, body },
    });

    if (!posted.ok) {
      return posted;
    }

    await refreshCaller(auth, [INCIDENTS_TAG]);

    return ok(posted.data.id);
  },
);

/** Resolves an incident with a closing update. */
export const resolveIncident = bsb.action(
  {
    input: v.object({ incidentId: Id, body: Text(2000) }),
    requireTenant: true,
    permission: "incidents.write",
  },
  async ({ incidentId, body }, { db, auth }) => {
    const resolved = await db.incidents.resolve({ incidentId, body });

    if (!resolved.ok) {
      return resolved;
    }

    await refreshCaller(auth, [INCIDENTS_TAG]);

    return ok(resolved.data.id);
  },
);
