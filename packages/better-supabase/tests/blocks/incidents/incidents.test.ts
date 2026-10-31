import * as v from "valibot";
import { describe, expect, it } from "vitest";

import {
  createIncidents,
  incidentChangesSchema,
  incidentInputSchema,
  incidentsBlock,
  postmortemInputSchema,
  statusComponentInputSchema,
  statusPageInputSchema,
} from "../../../src/blocks/incidents/index.ts";
import { fieldsTransport } from "../fields-transport.ts";

const AT = "2026-10-22T10:00:00Z";
const ID = "00000000-0000-4000-8000-000000000001";

const COMPONENT = {
  id: "c1",
  organizationId: "org-1",
  name: "API",
  description: "Public REST API",
  group: "Core",
  public: true,
  status: "degraded",
  position: 1,
  createdAt: AT,
  updatedAt: AT,
};

const BARE_COMPONENT = {
  id: "c2",
  organizationId: "org-1",
  name: "Billing",
  public: false,
  status: "operational",
  createdAt: AT,
  updatedAt: AT,
};

const INCIDENT = {
  id: "i1",
  organizationId: "org-1",
  title: "Elevated errors",
  description: "Database failover",
  severity: "sev2",
  status: "identified",
  public: true,
  commanderId: "u1",
  startedAt: AT,
  resolvedAt: AT,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
  impacts: [{ componentId: "c1", name: "API", impact: "partial_outage" }],
  fields: { team: "core" },
};

const BARE_INCIDENT = {
  id: "i2",
  organizationId: "org-1",
  title: "Slow dashboard",
  severity: "sev4",
  status: "investigating",
  public: false,
  startedAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const UPDATE = {
  id: "u1",
  incidentId: "i1",
  status: "monitoring",
  body: "A fix is out",
  public: true,
  authorId: "u1",
  createdAt: AT,
};

const POSTMORTEM = {
  id: "pm1",
  incidentId: "i1",
  summary: "Failover took too long",
  impact: "20 minutes of errors",
  rootCause: "A stuck replica",
  resolution: "Promoted a new primary",
  status: "published",
  publishedAt: AT,
  authorId: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_POSTMORTEM = {
  id: "pm2",
  incidentId: "i2",
  status: "draft",
  createdAt: AT,
  updatedAt: AT,
};

const PAGE = {
  id: "s1",
  organizationId: "org-1",
  slug: "acme",
  title: "Acme status",
  description: "Live status",
  published: true,
  createdAt: AT,
  updatedAt: AT,
};

const Fields = v.object({ team: v.picklist(["core", "edge"]) });

const validate = (
  schema: { "~standard": { validate: (value: unknown) => unknown } },
  value: unknown,
) => schema["~standard"].validate(value) as { issues?: unknown[] };

describe("createIncidents", () => {
  it("saves, deletes and lists components", async () => {
    const t = fieldsTransport({
      save_status_component: () => COMPONENT,
      delete_status_component: () => ({ id: "c2" }),
      list_status_components: () => [COMPONENT, BARE_COMPONENT],
    });

    const incidents = createIncidents({ transport: t });

    const saved = await incidents
      .saveComponent("org-1", {
        name: "API",
        description: "Public REST API",
        group: "Core",
        public: false,
        position: 1,
        componentId: "c1",
      })
      .orThrow();

    await incidents.saveComponent("org-1", { name: "Billing" }).orThrow();

    const deleted = await incidents.deleteComponent("c2").orThrow();
    const [, bare] = await incidents.components("org-1").orThrow();

    expect(saved).toMatchObject({
      description: "Public REST API",
      group: "Core",
      status: "degraded",
      position: 1,
    });
    expect(deleted).toEqual({ id: "c2" });
    expect(bare).toMatchObject({ public: false, position: 0 });
    expect(bare).not.toHaveProperty("group");
    expect(t.calls).toEqual([
      [
        "save_status_component",
        {
          tenant: "org-1",
          name: "API",
          description: "Public REST API",
          group_name: "Core",
          is_public: false,
          sort_position: 1,
          component_id: "c1",
        },
      ],
      [
        "save_status_component",
        {
          tenant: "org-1",
          name: "Billing",
          description: null,
          group_name: null,
          is_public: true,
          sort_position: 0,
          component_id: null,
        },
      ],
      ["delete_status_component", { component_id: "c2" }],
      ["list_status_components", { tenant: "org-1" }],
    ]);
  });

  it("opens an incident with its impacts and extra fields", async () => {
    const t = fieldsTransport({ open_incident: () => INCIDENT });
    const incidents = createIncidents({ transport: t, fields: Fields });

    const opened = await incidents
      .open("org-1", {
        title: "Elevated errors",
        description: "Database failover",
        severity: "sev2",
        public: true,
        commanderId: "u1",
        message: "Looking into it",
        impacts: [{ componentId: "c1", impact: "partial_outage" }],
        fields: { team: "core" },
      })
      .orThrow();

    await incidents.open("org-1", { title: "Quiet" }).orThrow();

    const refused = await incidents.open("org-1", {
      title: "Bad",
      // SAFETY: a value the schema refuses, to prove the client checks it.
      fields: { team: "ops" } as unknown as { team: "core" },
    });

    expect(opened).toMatchObject({
      severity: "sev2",
      status: "identified",
      commanderId: "u1",
      createdBy: "u1",
      fields: { team: "core" },
      impacts: [{ componentId: "c1", name: "API", impact: "partial_outage" }],
    });
    expect(opened.resolvedAt?.toString()).toBe(AT);
    expect(refused.ok ? undefined : refused.error.kind).toBe("validation");
    expect(t.calls).toEqual([
      [
        "open_incident",
        {
          tenant: "org-1",
          attrs: {
            title: "Elevated errors",
            description: "Database failover",
            severity: "sev2",
            public: true,
            commanderId: "u1",
            message: "Looking into it",
            impacts: [{ componentId: "c1", impact: "partial_outage" }],
          },
          fields: { team: "core" },
        },
      ],
      ["open_incident", { tenant: "org-1", attrs: { title: "Quiet" } }],
    ]);
  });

  it("updates an incident, posts to its timeline and replaces its impacts", async () => {
    const t = fieldsTransport({
      update_incident: () => ({ ...BARE_INCIDENT, fields: { team: "edge" } }),
      post_incident_update: () => UPDATE,
      set_incident_impacts: () => ({
        ...BARE_INCIDENT,
        fields: { team: "edge" },
      }),
    });

    const incidents = createIncidents({ transport: t, fields: Fields });

    const updated = await incidents
      .update("i2", { severity: "sev1" })
      .orThrow();

    await incidents.update("i2", { fields: { team: "edge" } }).orThrow();

    const posted = await incidents
      .postUpdate("i1", { status: "monitoring", body: "A fix is out" })
      .orThrow();

    await incidents
      .postUpdate("i1", { status: "resolved", body: "Fixed", public: false })
      .orThrow();
    await incidents.setImpacts("i2", []).orThrow();

    expect(updated).toMatchObject({ impacts: [], fields: { team: "edge" } });
    expect(updated).not.toHaveProperty("commanderId");
    expect(posted).toMatchObject({ authorId: "u1", public: true });
    expect(t.calls).toEqual([
      ["update_incident", { incident_id: "i2", attrs: { severity: "sev1" } }],
      [
        "update_incident",
        { incident_id: "i2", attrs: {}, fields: { team: "edge" } },
      ],
      [
        "post_incident_update",
        {
          incident_id: "i1",
          status: "monitoring",
          body: "A fix is out",
          is_public: null,
        },
      ],
      [
        "post_incident_update",
        {
          incident_id: "i1",
          status: "resolved",
          body: "Fixed",
          is_public: false,
        },
      ],
      ["set_incident_impacts", { incident_id: "i2", impacts: [] }],
    ]);
  });

  it("reads an incident with its timeline and postmortem", async () => {
    const t = fieldsTransport({
      get_incident: (args) => {
        switch (args["incident_id"]) {
          case "i1": {
            return {
              ...INCIDENT,
              updates: [UPDATE, { ...UPDATE, id: "u2", authorId: null }],
              postmortem: POSTMORTEM,
            };
          }

          case "i2": {
            return BARE_INCIDENT;
          }

          default: {
            return null;
          }
        }
      },
    });

    const incidents = createIncidents({ transport: t });

    const detail = await incidents.get("i1").orThrow();
    const bare = await incidents.get("i2").orThrow();
    const missing = await incidents.get("i9").orThrow();

    expect(detail?.updates.map((update) => update.id)).toEqual(["u1", "u2"]);
    expect(detail?.updates[1]).not.toHaveProperty("authorId");
    expect(detail?.postmortem).toMatchObject({ rootCause: "A stuck replica" });
    expect(bare?.updates).toEqual([]);
    expect(bare).not.toHaveProperty("postmortem");
    expect(missing).toBeUndefined();
  });

  it("lists incidents with and without filters", async () => {
    const t = fieldsTransport({ list_incidents: () => [INCIDENT] });
    const incidents = createIncidents({ transport: t });

    await incidents.list("org-1").orThrow();
    await incidents
      .list("org-1", {
        status: "open",
        severity: "sev1",
        componentId: "c1",
        before: Temporal.Instant.from(AT),
        pageSize: 25,
      })
      .orThrow();

    expect(t.calls).toEqual([
      [
        "list_incidents",
        {
          tenant: "org-1",
          status: null,
          severity: null,
          component_id: null,
          before: null,
          page_size: null,
        },
      ],
      [
        "list_incidents",
        {
          tenant: "org-1",
          status: "open",
          severity: "sev1",
          component_id: "c1",
          before: AT,
          page_size: 25,
        },
      ],
    ]);
  });

  it("drafts and publishes a postmortem", async () => {
    const t = fieldsTransport({
      save_incident_postmortem: () => BARE_POSTMORTEM,
      publish_incident_postmortem: () => POSTMORTEM,
    });

    const incidents = createIncidents({ transport: t });

    const draft = await incidents.savePostmortem("i2", {}).orThrow();

    await incidents
      .savePostmortem("i1", {
        summary: "Failover",
        impact: "Errors",
        rootCause: "Replica",
        resolution: "Promoted",
      })
      .orThrow();

    const published = await incidents.publishPostmortem("i1").orThrow();

    expect(draft).toMatchObject({ status: "draft" });
    expect(draft).not.toHaveProperty("summary");
    expect(published.publishedAt?.toString()).toBe(AT);
    expect(t.calls).toEqual([
      ["save_incident_postmortem", { incident_id: "i2", attrs: {} }],
      [
        "save_incident_postmortem",
        {
          incident_id: "i1",
          attrs: {
            summary: "Failover",
            impact: "Errors",
            rootCause: "Replica",
            resolution: "Promoted",
          },
        },
      ],
      ["publish_incident_postmortem", { incident_id: "i1" }],
    ]);
  });

  it("adds and removes postmortem action items as tasks", async () => {
    const action = {
      id: "a1",
      postmortemId: "pm1",
      taskId: "t1",
      title: "Alert on replica lag",
      state: "open",
      dueAt: AT,
      closedAt: null,
      createdAt: AT,
    };

    const t = fieldsTransport({
      add_incident_postmortem_action: () => action,
      remove_incident_postmortem_action: () => ({
        ...POSTMORTEM,
        actions: [{ ...action, id: "a2", dueAt: null }],
      }),
    });

    const incidents = createIncidents({ transport: t });

    const added = await incidents
      .addPostmortemAction("pm1", {
        title: "Alert on replica lag",
        assigneeId: "u1",
        dueAt: Temporal.Instant.from(AT),
      })
      .orThrow();

    await incidents.addPostmortemAction("pm1", { title: "Runbook" }).orThrow();
    const after = await incidents.removePostmortemAction("a1").orThrow();

    expect(added).toMatchObject({ taskId: "t1", state: "open" });
    expect(added.dueAt?.toString()).toBe(AT);
    expect(added).not.toHaveProperty("closedAt");
    expect(after.actions).toHaveLength(1);
    expect(after.actions[0]).not.toHaveProperty("dueAt");
    expect(t.calls).toEqual([
      [
        "add_incident_postmortem_action",
        {
          postmortem_id: "pm1",
          title: "Alert on replica lag",
          assignee_id: "u1",
          due_at: AT,
        },
      ],
      [
        "add_incident_postmortem_action",
        {
          postmortem_id: "pm1",
          title: "Runbook",
          assignee_id: null,
          due_at: null,
        },
      ],
      ["remove_incident_postmortem_action", { action_id: "a1" }],
    ]);
  });

  it("saves and reads the status page settings", async () => {
    const t = fieldsTransport({
      save_status_page: () => PAGE,
      get_status_page: (args) =>
        args["tenant"] === "org-1"
          ? { ...PAGE, description: null, published: false }
          : null,
    });

    const incidents = createIncidents({ transport: t });

    await incidents
      .saveStatusPage("org-1", {
        slug: "acme",
        title: "Acme status",
        description: "Live status",
        published: true,
      })
      .orThrow();
    await incidents
      .saveStatusPage("org-1", { slug: "acme", title: "Acme" })
      .orThrow();

    const page = await incidents.statusPage("org-1").orThrow();
    const none = await incidents.statusPage("org-2").orThrow();

    expect(page).toMatchObject({ slug: "acme", published: false });
    expect(page).not.toHaveProperty("description");
    expect(none).toBeUndefined();
    expect(t.calls.slice(0, 2)).toEqual([
      [
        "save_status_page",
        {
          tenant: "org-1",
          slug: "acme",
          title: "Acme status",
          description: "Live status",
          published: true,
        },
      ],
      [
        "save_status_page",
        {
          tenant: "org-1",
          slug: "acme",
          title: "Acme",
          description: null,
          published: false,
        },
      ],
    ]);
  });

  it("reads the public status page", async () => {
    const t = fieldsTransport({
      public_status_page: (args) =>
        args["slug"] === "acme"
          ? {
              slug: "acme",
              title: "Acme status",
              description: "Live status",
              days: 2,
              status: "partial_outage",
              components: [
                {
                  id: "c1",
                  name: "API",
                  description: "REST",
                  group: "Core",
                  status: "partial_outage",
                  uptimePercent: 99.5,
                  uptime: [
                    {
                      date: "2026-10-21",
                      status: "operational",
                      downMinutes: 0,
                    },
                    {
                      date: "2026-10-22",
                      status: "partial_outage",
                      downMinutes: "7",
                    },
                  ],
                },
                { id: "c2", name: "Web", status: "operational" },
              ],
              incidents: [
                {
                  id: "i1",
                  title: "Elevated errors",
                  severity: "sev2",
                  status: "resolved",
                  startedAt: AT,
                  resolvedAt: AT,
                  components: [
                    { id: "c1", name: "API", impact: "partial_outage" },
                  ],
                  updates: [
                    { status: "resolved", body: "Fixed", createdAt: AT },
                  ],
                  postmortem: { summary: "Failover", publishedAt: AT },
                },
                {
                  id: "i2",
                  title: "Investigating",
                  severity: "sev3",
                  status: "investigating",
                  startedAt: AT,
                  postmortem: null,
                },
              ],
            }
          : args["slug"] === "bare"
            ? { slug: "bare", title: "Bare", days: 90, status: "operational" }
            : null,
    });

    const incidents = createIncidents({ transport: t });

    const page = await incidents.publicStatusPage("acme", 2).orThrow();
    const bare = await incidents.publicStatusPage("bare").orThrow();
    const missing = await incidents.publicStatusPage("nope").orThrow();

    expect(page?.components[0]).toMatchObject({
      group: "Core",
      description: "REST",
      uptimePercent: 99.5,
    });
    expect(page?.components[0]?.uptime[1]).toMatchObject({
      status: "partial_outage",
      downMinutes: 7,
    });
    expect(page?.components[0]?.uptime[1]?.date.toString()).toBe("2026-10-22");
    expect(page?.components[1]).toEqual({
      id: "c2",
      name: "Web",
      status: "operational",
      uptimePercent: 100,
      uptime: [],
    });
    expect(page?.incidents[0]?.postmortem?.summary).toBe("Failover");
    expect(page?.incidents[0]?.resolvedAt?.toString()).toBe(AT);
    expect(page?.incidents[1]).toMatchObject({ components: [], updates: [] });
    expect(page?.incidents[1]).not.toHaveProperty("postmortem");
    expect(bare).toEqual({
      slug: "bare",
      title: "Bare",
      days: 90,
      status: "operational",
      components: [],
      incidents: [],
    });
    expect(missing).toBeUndefined();
    expect(t.calls.map(([, args]) => args)).toEqual([
      { slug: "acme", days: 2 },
      { slug: "bare", days: null },
      { slug: "nope", days: null },
    ]);
  });

  it("rejects malformed rows and stored fields the schema refuses", async () => {
    const t = fieldsTransport({
      get_incident: () => ({ ...BARE_INCIDENT, severity: "sev9" }),
      list_status_components: () => [{ ...COMPONENT, status: "down" }],
      publish_incident_postmortem: () => ({ ...POSTMORTEM, status: "final" }),
      list_incidents: () => [{ ...INCIDENT, fields: { team: "ops" } }],
    });

    const incidents = createIncidents({ transport: t, fields: Fields });

    expect((await incidents.get("i2")).ok).toBe(false);
    expect((await incidents.components("org-1")).ok).toBe(false);
    expect((await incidents.publishPostmortem("i1")).ok).toBe(false);

    const listed = await incidents.list("org-1");

    expect(listed.ok ? undefined : listed.error.kind).toBe("validation");
  });

  it("runs the hooks and logs through the logger", async () => {
    const seen: string[] = [];

    const incidents = createIncidents({
      transport: fieldsTransport({ list_status_components: () => [] }),
      logger: {
        error: () => undefined,
        warn: () => undefined,
        info: () => undefined,
        debug: () => undefined,
      },
      hooks: {
        components: {
          after: () => {
            seen.push("components");
          },
        },
      },
    });

    await incidents.components("org-1").orThrow();

    expect(seen).toEqual(["components"]);
  });
});

describe("incidents block", () => {
  it("names the block and validates the inputs", () => {
    expect(incidentsBlock.name).toBe("incidents");
    expect(
      validate(incidentInputSchema, {
        title: "Errors",
        severity: "sev2",
        impacts: [{ componentId: ID, impact: "degraded" }],
      }).issues,
    ).toBeUndefined();
    expect(
      validate(incidentInputSchema, { title: "Errors", severity: "sev9" })
        .issues,
    ).toBeDefined();
    expect(validate(incidentChangesSchema, {}).issues).toBeUndefined();
    expect(
      validate(statusComponentInputSchema, { name: "" }).issues,
    ).toBeDefined();
    expect(
      validate(postmortemInputSchema, { summary: "Failover" }).issues,
    ).toBeUndefined();
    expect(
      validate(statusPageInputSchema, { slug: "acme", title: "Acme" }).issues,
    ).toBeUndefined();
  });
});
