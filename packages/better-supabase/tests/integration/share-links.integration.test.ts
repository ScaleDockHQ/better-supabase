import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { ShareLinks } from "../../src/blocks/share-links/share-links.ts";
import type { TestUser } from "./block-session.ts";

import { createShareLinks } from "../../src/blocks/share-links/share-links.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("share-links block in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let links: ShareLinks;
  let foreignLinks: ShareLinks;
  let owner: TestUser;
  let outsider: TestUser;
  let org: string;
  let otherOrg: string;

  const doc = async (name: string): Promise<string> => {
    await session.service();

    const [row] = await session.rows<{ id: string }>(
      "insert into public.bsb_test_docs (organization_id, name) values ($1, $2) returning id::text as id",
      [org, name],
    );

    return row!.id;
  };

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.rows(
      `create table if not exists public.bsb_test_docs (
         id uuid primary key default gen_random_uuid(),
         organization_id uuid not null,
         name text not null
       );
       alter table public.bsb_test_docs enable row level security;`,
    );
    await session.install(["organizations", "share-links"], {
      modules: {
        "share-links": {
          options: { subjects: { doc: { table: "bsb_test_docs" } } },
        },
      },
    });
    owner = await session.user("owner");
    outsider = await session.user("outsider");
    org = await session.organization(owner);
    otherOrg = await session.organization(outsider);
    links = createShareLinks({
      transport: sqlTransport(session.sql),
      tenant: org,
    });
    foreignLinks = createShareLinks({
      transport: sqlTransport(session.sql),
      tenant: otherOrg,
    });
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("stores an expiry and returns it with the organization", async () => {
    const d1 = await doc("d1");
    await session.as(owner);
    const expiresAt = Temporal.Now.instant().add({ hours: 1 }).round("second");

    const link = await links
      .create({ type: "doc", id: d1 }, { expiresAt })
      .orThrow();

    await session.as("anon");
    const resolved = await links.resolve(link.token).orThrow();
    expect(resolved).toMatchObject({
      id: link.id,
      organizationId: org,
      subject: { type: "doc", id: d1 },
      role: "view",
    });
    expect(resolved?.expiresAt?.equals(expiresAt)).toBe(true);
  });

  it("refuses an expiry in the past and stops resolving after one", async () => {
    const d1 = await doc("d1");
    await session.as(owner);

    const past = await links.create(
      { type: "doc", id: d1 },
      { expiresAt: Temporal.Now.instant().subtract({ minutes: 1 }) },
    );

    expect(past.ok ? undefined : past.error.hint).toBe("SHARE_EXPIRY_INVALID");
    const link = await links.create({ type: "doc", id: d1 }).orThrow();
    await session.service();
    await session.client.query(
      "update better_supabase.share_links set expires_at = now() - interval '1 second' where id = $1",
      [link.id],
    );
    await session.as("anon");
    expect(await links.resolve(link.token).orThrow()).toBeNull();
  });

  it("refuses a subject of another organization or an unknown type", async () => {
    const d1 = await doc("d1");
    await session.as(outsider);

    const foreign = await foreignLinks.create({ type: "doc", id: d1 });

    expect(foreign.ok ? undefined : foreign.error.hint).toBe(
      "SHARE_SUBJECT_NOT_FOUND",
    );
    const unknown = await foreignLinks.create({ type: "invoice", id: d1 });
    expect(unknown.ok ? undefined : unknown.error.hint).toBe(
      "SHARE_SUBJECT_UNKNOWN",
    );
  });

  it("stops resolving a link once its uses are spent", async () => {
    const d1 = await doc("d1");
    await session.as(owner);

    const link = await links
      .create({ type: "doc", id: d1 }, { maxUses: 2 })
      .orThrow();

    await session.as("anon");
    expect(await links.resolve(link.token).orThrow()).toMatchObject({
      maxUses: 2,
    });
    expect(await links.resolve(link.token).orThrow()).not.toBeNull();
    expect(await links.resolve(link.token).orThrow()).toBeNull();
  });

  it("lets only the creator or a manager revoke a link", async () => {
    const d2 = await doc("d2");
    await session.as(owner);
    const link = await links.create({ type: "doc", id: d2 }).orThrow();
    await session.as(outsider);
    const refused = await links.revoke(link.id);
    expect(refused.ok ? undefined : refused.error.hint).toBe("SHARE_NOT_FOUND");
    await session.as(owner);
    expect(await links.revoke(link.id).orThrow()).toBe(true);
  });

  it("lists links only to their organization", async () => {
    const d3 = await doc("d3");
    await session.as(owner);
    await links.create({ type: "doc", id: d3 }).orThrow();
    expect(await links.list({ type: "doc", id: d3 }).orThrow()).toHaveLength(1);
    await session.as(outsider);
    expect(await links.list({ type: "doc", id: d3 }).orThrow()).toEqual([]);
  });

  it("records views for members only", async () => {
    await session.as(outsider);

    const refused = await links.recordView(
      { type: "doc", id: "d1" },
      "user",
      outsider.id,
    );

    expect(refused.ok ? undefined : refused.error.hint).toBe("SHARE_FORBIDDEN");
    await session.as(owner);
    expect(
      await links
        .recordView({ type: "doc", id: "d1" }, "user", owner.id)
        .orThrow(),
    ).toBe(true);
  });
});
