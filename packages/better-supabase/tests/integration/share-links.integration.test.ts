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
  let owner: TestUser;
  let outsider: TestUser;
  let org: string;

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(["organizations", "share-links"]);
    owner = await session.user("owner");
    outsider = await session.user("outsider");
    org = await session.organization(owner);
    links = createShareLinks({ transport: sqlTransport(session.sql) });
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("stores an expiry and returns it with the organization", async () => {
    await session.as(owner);
    const expiresAt = Temporal.Now.instant().add({ hours: 1 }).round("second");
    const link = await links.create(org, "doc", "d1", { expiresAt }).orThrow();
    await session.as("anon");
    const resolved = await links.resolve(link.token).orThrow();
    expect(resolved).toMatchObject({
      id: link.id,
      organizationId: org,
      subjectType: "doc",
      subjectId: "d1",
      role: "view",
    });
    expect(resolved?.expiresAt?.equals(expiresAt)).toBe(true);
  });

  it("refuses an expiry in the past and stops resolving after one", async () => {
    await session.as(owner);

    const past = await links.create(org, "doc", "d1", {
      expiresAt: Temporal.Now.instant().subtract({ minutes: 1 }),
    });

    expect(past.ok ? undefined : past.error.hint).toBe("SHARE_EXPIRY_INVALID");
    const link = await links.create(org, "doc", "d1").orThrow();
    await session.service();
    await session.client.query(
      "update better_supabase.share_links set expires_at = now() - interval '1 second' where id = $1",
      [link.id],
    );
    await session.as("anon");
    expect(await links.resolve(link.token).orThrow()).toBeNull();
  });

  it("lets only the creator or a manager revoke a link", async () => {
    await session.as(owner);
    const link = await links.create(org, "doc", "d2").orThrow();
    await session.as(outsider);
    const refused = await links.revoke(link.id);
    expect(refused.ok ? undefined : refused.error.hint).toBe("SHARE_NOT_FOUND");
    await session.as(owner);
    expect(await links.revoke(link.id).orThrow()).toBe(true);
  });

  it("lists links only to their organization", async () => {
    await session.as(owner);
    await links.create(org, "doc", "d3").orThrow();
    expect(await links.list("doc", "d3").orThrow()).toHaveLength(1);
    await session.as(outsider);
    expect(await links.list("doc", "d3").orThrow()).toEqual([]);
  });

  it("records views for members only", async () => {
    await session.as(outsider);

    const refused = await links.recordView(
      org,
      "doc",
      "d1",
      "user",
      outsider.id,
    );

    expect(refused.ok ? undefined : refused.error.hint).toBe("SHARE_FORBIDDEN");
    await session.as(owner);
    expect(
      await links.recordView(org, "doc", "d1", "user", owner.id).orThrow(),
    ).toBe(true);
  });
});
