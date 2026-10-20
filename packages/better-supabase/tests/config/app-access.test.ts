import { describe, expect, it } from "vitest";

import { appTablesOf } from "../../src/config/app-tables.ts";

const fails = (value: unknown, message: string): void => {
  expect(() => appTablesOf(value)).toThrow(
    expect.objectContaining({
      name: "TypeError",
      message: expect.stringContaining(message),
    }),
  );
};

const projects = (extra: Record<string, unknown> = {}) => ({
  columns: {
    name: { type: "text", nullable: false },
    budget: { type: "numeric", access: "read" },
    internal_notes: { type: "text", access: "server" },
  },
  ...extra,
});

describe("appTablesOf column access", () => {
  it("keeps read and server", () => {
    const tables = appTablesOf({ projects: projects() });

    expect(tables["projects"]?.columns?.["budget"]?.access).toBe("read");
    expect(tables["projects"]?.columns?.["internal_notes"]?.access).toBe(
      "server",
    );
  });

  it("refuses another value", () => {
    fails(
      { a: { columns: { b: { type: "text", access: "write" } } } },
      "appTables.a.columns.b.access must be one of read, server",
    );
  });

  it("refuses a required restricted column without a default", () => {
    fails(
      {
        a: {
          columns: { b: { type: "text", nullable: false, access: "read" } },
        },
      },
      "a required one needs a default",
    );

    expect(() =>
      appTablesOf({
        a: {
          columns: {
            b: {
              type: "text",
              nullable: false,
              access: "server",
              default: "'x'",
            },
            n: { type: "bigint", identity: true, access: "read" },
          },
        },
      }),
    ).not.toThrow();
  });

  it("refuses a server column where signed-in users read it", () => {
    const subject = (value: Record<string, unknown>) => ({
      projects: projects({ subject: { type: "project", ...value } }),
    });

    fails(subject({ title: "internal_notes" }), "subject.title");
    fails(
      subject({ search: { body: ["internal_notes"] } }),
      "subject.search.body",
    );
    fails(subject({ url: "/p/{internal_notes}" }), "subject.url");
    fails(
      subject({ versions: { columns: ["internal_notes"] } }),
      "subject.versions.columns",
    );
    fails(subject({ versions: true }), "list subject.versions.columns");
    fails(
      { projects: projects({ events: { include: ["internal_notes"] } }) },
      "events.include",
    );
  });

  it("refuses a server column in another table's rollup or lookup", () => {
    fails(
      {
        projects: projects(),
        tasks: {
          columns: {
            project_id: { type: "uuid", references: { table: "projects" } },
          },
          lookups: { notes: { via: "project_id", column: "internal_notes" } },
        },
      },
      "projects.internal_notes has access server",
    );

    fails(
      {
        projects: projects({
          rollups: {
            hours: {
              table: "tasks",
              via: "project_id",
              aggregate: "sum",
              column: "secret_hours",
            },
          },
        }),
        tasks: {
          columns: {
            project_id: { type: "uuid", references: { table: "projects" } },
            secret_hours: { type: "numeric", access: "server" },
          },
        },
      },
      "tasks.secret_hours has access server",
    );
  });

  it("lets a read column be read everywhere", () => {
    expect(() =>
      appTablesOf({
        projects: projects({
          subject: {
            type: "project",
            title: "budget",
            versions: { columns: ["name", "budget"] },
          },
          events: { include: ["budget"] },
        }),
      }),
    ).not.toThrow();
  });
});
