import { Pool } from "pg";
import { afterAll, afterEach, beforeEach, describe, expect, it } from "vitest";

import type { LifecycleStorage } from "../../src/blocks/data-lifecycle/index.ts";
import type { AppTablesConfig } from "../../src/config/types/app-tables.ts";
import type { BlockSqlLayout } from "../../src/sql/module-types.ts";
import type { TestUser } from "./block-session.ts";

import {
  createDataExporter,
  createDataLifecycle,
  sqlTransport,
} from "../../src/blocks/data-lifecycle/index.ts";
import { withAppTableSubjects } from "../../src/config/app-tables.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

// A record export reads the record's row through its reveal function as the
// caller, so encrypted columns arrive decrypted and the read is audited.
const TABLES: AppTablesConfig = {
  it_charts: {
    columns: {
      title: { type: "text", nullable: false },
      diagnosis: { type: "text", encrypted: true },
    },
    auditReads: true,
    subject: {
      type: "it_chart",
      title: "title",
      permissions: { manage: "charts.manage" },
    },
  },
};

const BLOCKS = [
  "memberships",
  "permissions",
  "organizations",
  "updated-at",
  "audit",
  "outbox",
  "subjects",
  "field-encryption",
  "custom-fields",
  "data-lifecycle",
];

const LAYOUT: BlockSqlLayout = {
  appTables: TABLES,
  subjects: withAppTableSubjects({}, TABLES, undefined),
  modules: {
    permissions: {
      roles: {
        owner: ["*"],
        admin: ["organization.read", "members.read", "charts.manage"],
        member: ["organization.read", "members.read"],
      },
    },
  },
};

function memoryStorage(): {
  readonly files: Map<string, string>;
  readonly storage: LifecycleStorage;
} {
  const files = new Map<string, string>();

  return {
    files,
    storage: {
      from: () => ({
        upload: async (path, body) => {
          files.set(path, await body.text());

          return { data: { path }, error: null };
        },
        createSignedUrl: (path) =>
          Promise.resolve({
            data: { signedUrl: `https://storage.test/${path}` },
            error: null,
          }),
        list: () => Promise.resolve({ data: [], error: null }),
        remove: () => Promise.resolve({ data: [], error: null }),
      }),
    },
  };
}

const lines = (text: string | undefined): Record<string, unknown>[] =>
  (text ?? "")
    .trim()
    .split("\n")
    .filter((line) => line.length > 0)
    .map((line) => JSON.parse(line) as Record<string, unknown>);

describe.skipIf(!live)("subject export", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });
  let s: BlockSession;
  let ann: TestUser;
  let ada: TestUser;
  let max: TestUser;
  let org: string;
  let chart: string;
  let other: string;

  beforeEach(async () => {
    s = await BlockSession.open(pool);
    await s.install(BLOCKS, LAYOUT);
    ann = await s.user("ann");
    ada = await s.user("ada");
    max = await s.user("max");
    org = await s.organization(ann, { admin: ada, member: max });

    await s.asRole(ann);

    for (const [title, diagnosis] of [
      ["A", "asthma"],
      ["B", "flu"],
    ]) {
      await s.client.query(
        "insert into public.it_charts (organization_id, title, diagnosis) values ($1, $2, $3)",
        [org, title, diagnosis],
      );
    }

    await s.service();
    [chart, other] = (
      await s.rows<{ id: string }>(
        "select id::text from public.it_charts order by title",
      )
    ).map((row) => row.id) as [string, string];

    await s.asRole(ann);

    const definition = await s.value<string>(
      "(better_supabase.save_field_definition($1, 'it_chart', 'ward', 'Ward', 'text', false) ->> 'id')",
      [org],
    );

    for (const [id, ward] of [
      [chart, "north"],
      [other, "south"],
    ]) {
      await s.client.query(
        "select better_supabase.set_field_value($1, 'it_chart', $2, $3, $4)",
        [org, id, definition, ward],
      );
    }
  });

  afterEach(async () => {
    await s.close();
  });

  afterAll(async () => {
    await pool.end();
  });

  it("exports one record decrypted, with its custom field values, and audits the read", async () => {
    const lifecycle = createDataLifecycle({ transport: sqlTransport(s.sql) });

    await s.asRole(ann);

    const requested = await lifecycle
      .requestSubjectExport({ subjectType: "it_chart", subjectId: chart })
      .orThrow();

    expect(requested).toMatchObject({
      subject: "record",
      subjectType: "it_chart",
      subjectId: chart,
      organizationId: org,
      userId: undefined,
      format: "ndjson",
      status: "pending",
    });
    expect(
      (
        await lifecycle
          .requestSubjectExport({ subjectType: "it_chart", subjectId: chart })
          .orThrow()
      ).id,
    ).toBe(requested.id);
    expect(
      (await lifecycle.exports(org).orThrow()).map((row) => row.id),
    ).toContain(requested.id);

    await s.service();

    const memory = memoryStorage();

    const exporter = createDataExporter({
      transport: sqlTransport(s.sql),
      storage: memory.storage,
      pageSize: 1,
    });

    const ready = await exporter.run({ exportId: requested.id }).orThrow();

    expect(ready.files.toSorted()).toEqual([
      `${requested.id}/better_supabase.field_values.ndjson`,
      `${requested.id}/public.it_charts.ndjson`,
    ]);

    const record = lines(
      memory.files.get(`${requested.id}/public.it_charts.ndjson`),
    );

    expect(record).toHaveLength(1);
    expect(record[0]).toMatchObject({
      id: chart,
      title: "A",
      diagnosis: "asthma",
    });

    const values = lines(
      memory.files.get(`${requested.id}/better_supabase.field_values.ndjson`),
    );

    expect(values.map((row) => row["value_text"])).toEqual(["north"]);

    expect(
      await s.value<number>(
        "(select count(*)::int from better_supabase.audit_events where event_type = 'it_chart.viewed' and actor_id = $1 and organization_id = $2)",
        [ann.id, org],
      ),
    ).toBe(1);
    expect(
      await s.value<number>(
        "(select count(*)::int from better_supabase.data_export_contents where export_id = $1)",
        [requested.id],
      ),
    ).toBe(0);

    const events = await s.rows<{ type: string; payload: object }>(
      "select type, payload from better_supabase.outbox_events where type like 'data_export.%' order by position",
    );

    expect(events.map((event) => event.type)).toEqual([
      "data_export.requested",
      "data_export.completed",
    ]);
    expect(events[0]!.payload).toMatchObject({
      subject: "record",
      subjectType: "it_chart",
      subjectId: chart,
    });
  });

  it("lets the record's manage action export it as CSV and refuses everyone else", async () => {
    const lifecycle = createDataLifecycle({ transport: sqlTransport(s.sql) });

    await s.asRole(max);

    const refused = await lifecycle.requestSubjectExport({
      subjectType: "it_chart",
      subjectId: chart,
    });

    expect(refused.ok ? undefined : refused.error.hint).toBe(
      "DATA_EXPORT_FORBIDDEN",
    );

    const missing = await lifecycle.requestSubjectExport({
      subjectType: "it_chart",
      subjectId: crypto.randomUUID(),
    });

    expect(missing.ok ? undefined : missing.error.hint).toBe(
      "DATA_EXPORT_FORBIDDEN",
    );

    expect(
      await s.hint(
        "select better_supabase.request_subject_export('it_nothing', $1)",
        [chart],
      ),
    ).toBe("DATA_EXPORT_SUBJECT");
    expect(
      await s.hint(
        "select better_supabase.request_subject_export('it_chart', $1, 'xml')",
        [chart],
      ),
    ).toBe("DATA_EXPORT_FORMAT");

    await s.asRole("anon");
    expect(
      await s.hint(
        "select better_supabase.request_subject_export('it_chart', $1)",
        [chart],
      ),
    ).toMatch(/permission denied/u);

    await s.asRole(ada);

    const managed = await lifecycle
      .requestSubjectExport({
        subjectType: "it_chart",
        subjectId: chart,
        format: "csv",
      })
      .orThrow();

    expect(managed).toMatchObject({ subject: "record", format: "csv" });

    await s.service();

    const memory = memoryStorage();

    const exporter = createDataExporter({
      transport: sqlTransport(s.sql),
      storage: memory.storage,
    });

    const ready = await exporter.run({ exportId: managed.id }).orThrow();

    expect(ready.files).toContain(`${managed.id}/public.it_charts.csv`);
    expect(memory.files.get(`${managed.id}/public.it_charts.csv`)).toContain(
      "asthma",
    );
  });
});
