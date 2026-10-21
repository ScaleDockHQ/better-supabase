import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { TestUser } from "./block-session.ts";

import { createAudit } from "../../src/blocks/audit/index.ts";
import { createUndo } from "../../src/blocks/undo/undo.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const note = (n: number): string =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

describe.skipIf(!live)("audit revert in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let db: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let org: string;

  const lastEntry = async (): Promise<string> => {
    await db.service();

    return db.value<string>(
      `(select max(id)::text from better_supabase.audit_events where table_name like 'revert_it.%')`,
    );
  };

  const title = async (n: number): Promise<string | null> => {
    await db.service();

    return db.value<string | null>(
      `(select title from revert_it.notes where id = '${note(n)}')`,
    );
  };

  const revert = (...entries: string[]): string =>
    `better_supabase.revert_audit_entries(array[${entries.map((e) => `'${e}'`).join(", ")}]::text[])`;

  beforeAll(async () => {
    db = await BlockSession.open(pool);
    await db.client.query(`create schema revert_it;
create table revert_it.notes (
  id uuid primary key,
  organization_id uuid not null,
  title text,
  secret text
);
alter table revert_it.notes enable row level security;
create policy notes_all on revert_it.notes for all to authenticated using (true) with check (true);
grant usage on schema revert_it to authenticated;
grant select, insert, update, delete on revert_it.notes to authenticated;
create table revert_it.labels (
  id uuid primary key,
  organization_id uuid not null,
  name text,
  position bigint generated always as identity
);
alter table revert_it.labels enable row level security;
create policy labels_all on revert_it.labels for all to authenticated using (true) with check (true);
grant select, insert, update, delete on revert_it.labels to authenticated;`);
    await db.install(["organizations", "audit"], {
      modules: { organizations: { audit: false } },
    });
    await db.client.query(
      "select better_supabase.audit('revert_it.notes', redact => '{secret}'); select better_supabase.audit('revert_it.labels')",
    );
    owner = await db.user("owner");
    member = await db.user("member");
    org = await db.organization(owner, { member });
  });

  afterAll(async () => {
    await db.close();
    await pool.end();
  });

  const write = async (statement: string): Promise<string> => {
    await db.asRole(owner);
    await db.client.query(statement);

    return lastEntry();
  };

  it("needs audit.revert in the entry's tenant", async () => {
    const entry = await write(
      `insert into revert_it.notes (id, organization_id, title) values ('${note(1)}', '${org}', 'one')`,
    );

    await db.asRole(member);
    expect(await db.hint(revert(entry))).toBe("AUDIT_ENTRY_NOT_FOUND");
  });

  it("restores an update and returns the entries an undo reverts", async () => {
    await write(
      `insert into revert_it.notes (id, organization_id, title) values ('${note(2)}', '${org}', 'draft')`,
    );

    const entry = await write(
      `update revert_it.notes set title = 'final' where id = '${note(2)}'`,
    );

    await db.asRole(owner);

    const result = await db.value<{ reverted: number; entries: string[] }>(
      revert(entry),
    );

    expect(result.reverted).toBe(1);
    expect(result.entries).toHaveLength(1);
    expect(await title(2)).toBe("draft");

    await db.asRole(owner);
    await db.value(revert(...result.entries));
    expect(await title(2)).toBe("final");
  });

  it("refuses when the row changed after the entry", async () => {
    await write(
      `insert into revert_it.notes (id, organization_id, title) values ('${note(3)}', '${org}', 'a')`,
    );

    const entry = await write(
      `update revert_it.notes set title = 'b' where id = '${note(3)}'`,
    );

    await write(
      `update revert_it.notes set title = 'c' where id = '${note(3)}'`,
    );
    await db.asRole(owner);
    expect(await db.hint(revert(entry))).toBe("ROW_CHANGED_SINCE");
  });

  it("deletes an inserted row and inserts a deleted one", async () => {
    const inserted = await write(
      `insert into revert_it.notes (id, organization_id, title) values ('${note(4)}', '${org}', 'new')`,
    );

    await db.asRole(owner);
    await db.value(revert(inserted));
    expect(await title(4)).toBeNull();

    await write(
      `insert into revert_it.labels (id, organization_id, name) values ('${note(5)}', '${org}', 'kept')`,
    );

    const deleted = await write(
      `delete from revert_it.labels where id = '${note(5)}'`,
    );

    await db.asRole(owner);
    await db.value(revert(deleted));
    await db.service();
    expect(
      await db.rows(
        `select name, position from revert_it.labels where id = '${note(5)}'`,
      ),
    ).toEqual([{ name: "kept", position: "1" }]);
  });

  it("refuses redacted values and events", async () => {
    await write(
      `insert into revert_it.notes (id, organization_id, title) values ('${note(6)}', '${org}', 's')`,
    );

    const secret = await write(
      `update revert_it.notes set secret = 'x' where id = '${note(6)}'`,
    );

    await db.asRole(owner);
    expect(await db.hint(revert(secret))).toBe("AUDIT_ENTRY_REDACTED");

    const deleted = await write(
      `delete from revert_it.notes where id = '${note(6)}'`,
    );

    await db.asRole(owner);
    expect(await db.hint(revert(deleted))).toBe("AUDIT_ENTRY_REDACTED");

    await db.service();

    const event = await db.value<string>(
      `better_supabase.audit_event('note.shared', tenant => '${org}')::text`,
    );

    await db.asRole(owner);
    expect(await db.hint(revert(event))).toBe("AUDIT_ENTRY_NOT_REVERTIBLE");
  });

  it("reverts and undoes through the client", async () => {
    await write(
      `insert into revert_it.notes (id, organization_id, title) values ('${note(7)}', '${org}', 'before')`,
    );

    const entry = await write(
      `update revert_it.notes set title = 'after' where id = '${note(7)}'`,
    );

    await db.asRole(owner);
    const transport = sqlTransport(db.sql);
    const reverted = await createAudit({ transport }).revert([entry]).orThrow();
    expect(reverted.reverted).toBe(1);
    expect(await title(7)).toBe("before");
    expect(reverted.undo).not.toBeNull();

    await db.asRole(owner);
    await createUndo({ transport }).apply(reverted.undo!).orThrow();
    expect(await title(7)).toBe("after");
  });
});
