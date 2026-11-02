import { Pool } from "pg";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

import type { Assets } from "../../src/blocks/assets/index.ts";
import type { TestUser } from "./block-session.ts";

import { createAssets } from "../../src/blocks/assets/index.ts";
import { sqlTransport } from "../../src/core/block-transport.ts";
import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

describe.skipIf(!live)("assets module in Postgres", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 1 });
  let session: BlockSession;
  let owner: TestUser;
  let member: TestUser;
  let outsider: TestUser;
  let tenant: string;
  let assets: Assets;

  const events = async (type: string): Promise<Record<string, unknown>[]> =>
    (
      await session.rows<{ data: Record<string, unknown> }>(
        "select payload as data from better_supabase.outbox_events where organization_id = $1 and type = $2 order by position",
        [tenant, type],
      )
    ).map((row) => row.data);

  beforeAll(async () => {
    session = await BlockSession.open(pool);
    await session.install(["organizations", "bookings", "assets", "outbox"]);
    owner = await session.user("assets-owner");
    member = await session.user("assets-member");
    outsider = await session.user("assets-outsider");
    tenant = await session.organization(owner, { member });
    await session.organization(outsider);
    await session.as(owner);
    assets = createAssets({ transport: sqlTransport(session.sql), tenant });
  });

  afterAll(async () => {
    await session.close();
    await pool.end();
  });

  it("builds a location tree and keeps it free of cycles", async () => {
    await session.as(owner);

    const site = await assets
      .createLocation({
        kind: "site",
        name: "HQ",
        code: "HQ",
        point: { latitude: 52.37, longitude: 4.89 },
      })
      .orThrow();

    const floor = await assets
      .createLocation({ kind: "floor", name: "1", parentId: site.id })
      .orThrow();

    expect(await assets.location(floor.id).orThrow()).toMatchObject({
      path: [
        { id: site.id, name: "HQ" },
        { id: floor.id, name: "1" },
      ],
      locations: 0,
      assets: 0,
    });
    expect(
      await assets.updateLocation({
        locationId: site.id,
        patch: { parentId: floor.id },
      }),
    ).toMatchObject({ ok: false, error: { hint: "ASSETS_LOCATION_CYCLE" } });
    expect(
      await assets.createLocation({ kind: "site", name: "Dup", code: "HQ" }),
    ).toMatchObject({ ok: false, error: { hint: "ASSETS_CODE_TAKEN" } });
    expect(await assets.locations().orThrow()).toHaveLength(1);
    expect(await assets.locations({ parentId: site.id }).orThrow()).toEqual([
      expect.objectContaining({ id: floor.id }),
    ]);
    expect(await events("asset_location.created")).toHaveLength(2);
  });

  it("assigns an asset, finds it nearby and links a booking resource", async () => {
    await session.as(owner);

    const site = await assets
      .createLocation({ kind: "site", name: "Depot" })
      .orThrow();

    const van = await assets
      .createAsset({
        kind: "van",
        name: "Van 1",
        locationId: site.id,
        tag: "VAN-1",
        point: { latitude: 51.92, longitude: 4.48 },
      })
      .orThrow();

    const assigned = await assets
      .assign({
        assetId: van.id,
        assignee: { type: "member", id: member.id },
        note: "route A",
      })
      .orThrow();

    expect(assigned.assignee).toEqual({ type: "member", id: member.id });
    expect(
      await assets.assign({
        assetId: van.id,
        assignee: { type: "member", id: outsider.id },
      }),
    ).toMatchObject({ ok: false, error: { hint: "ASSETS_ASSIGNEE_INVALID" } });

    const near = await assets
      .near({ latitude: 51.921, longitude: 4.481, radiusMeters: 500 })
      .orThrow();

    expect(near.assets.map((asset) => asset.id)).toEqual([van.id]);
    expect(near.assets[0]?.distanceMeters).toBeGreaterThan(0);
    expect(
      await assets.locationsAt({ latitude: 51.92, longitude: 4.48 }),
    ).toMatchObject({ ok: false, error: { hint: "ASSETS_POSTGIS_REQUIRED" } });

    const [resource] = await session.rows<{ id: string }>(
      "insert into better_supabase.booking_resources (tenant_id, name) values ($1, 'Van bay') returning id",
      [tenant],
    );

    if (!resource) {
      throw new Error("no booking resource");
    }

    await assets
      .link({
        target: { type: "booking_resource", id: resource.id },
        assetId: van.id,
      })
      .orThrow();
    expect((await assets.asset(van.id).orThrow()).links).toMatchObject({
      bookingResources: [{ id: resource.id, name: "Van bay" }],
    });

    await session.as(member);

    const memberAssets = createAssets({
      transport: sqlTransport(session.sql),
      tenant,
    });

    expect(
      (
        await memberAssets
          .assignedTo({ assignee: { type: "member", id: member.id } })
          .orThrow()
      ).map((asset) => asset.id),
    ).toEqual([van.id]);
    expect(
      await memberAssets.createAsset({ kind: "van", name: "Mine" }),
    ).toMatchObject({ ok: false, error: { hint: "ASSETS_FORBIDDEN" } });

    await session.as(owner);

    const retired = await assets
      .updateAsset({ assetId: van.id, patch: { status: "retired" } })
      .orThrow();

    expect(retired.assignee).toBeUndefined();
    expect(await assets.assignments({ assetId: van.id }).orThrow()).toEqual([
      expect.objectContaining({
        note: "route A",
        releasedAt: expect.anything(),
      }),
    ]);
    expect(
      await assets.assign({
        assetId: van.id,
        assignee: { type: "member", id: member.id },
      }),
    ).toMatchObject({ ok: false, error: { hint: "ASSETS_RETIRED" } });
    expect(await events("asset.assigned")).toEqual([
      expect.objectContaining({ id: van.id, assigneeId: member.id }),
    ]);
    expect(await assets.archiveLocation(site.id).orThrow()).toMatchObject({
      id: site.id,
    });
  });

  it("hides one organization's assets from another", async () => {
    await session.asRole(outsider);
    expect(
      await session.value<number>(
        "(select count(*)::integer from better_supabase.assets) + (select count(*)::integer from better_supabase.asset_locations)",
      ),
    ).toBe(0);
  });
});
