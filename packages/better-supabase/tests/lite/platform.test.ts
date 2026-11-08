import { describe, expect, it } from "vitest";

import type { LiteConnection } from "../../src/lite/runtime.ts";

import { migrateLite } from "../../src/lite/runtime.ts";

function connection(pglite: boolean): {
  readonly sent: string[];
  readonly connection: LiteConnection;
} {
  const sent: string[] = [];

  const base: LiteConnection = {
    createMigrator: (sql) => {
      sent.push(sql);

      return { migrate: () => Promise.resolve() };
    },
    translateDdl: () => Promise.resolve(""),
    transaction: () => Promise.resolve(),
    close: () => Promise.resolve(),
  };

  // SAFETY: PGlite connections carry a `driver`; the shim check reads only that key.
  const withDriver = { ...base, driver: {} } as unknown as LiteConnection;

  return { sent, connection: pglite ? withDriver : base };
}

describe("migrateLite", () => {
  it("adds the Realtime and Storage tables a schema uses and does not create", async () => {
    const { sent, connection: lite } = connection(true);

    await migrateLite(lite, [
      "create policy p on realtime.messages using (true);",
      "create policy q on storage.objects using (true);",
    ]);

    expect(sent[0]).toContain("create table if not exists realtime.messages");
    expect(sent[0]).toContain("create table if not exists storage.objects");
  });

  it("leaves a schema that creates its own tables alone", async () => {
    const { sent, connection: lite } = connection(true);

    await migrateLite(lite, [
      "create schema realtime; create table realtime.messages (id int);",
    ]);

    expect(sent[0]).not.toContain("if not exists realtime.messages");
  });

  it("adds nothing for a schema that names neither, or on another driver", async () => {
    const plain = connection(true);
    await migrateLite(plain.connection, ["create table t (id int);"]);
    expect(plain.sent[0]).toBe("create table t (id int);");

    const other = connection(false);
    await migrateLite(other.connection, ["select realtime.topic();"]);
    expect(other.sent[0]).toBe("select realtime.topic();");

    await migrateLite(other.connection, [" "]);
    expect(other.sent).toHaveLength(1);
  });
});
