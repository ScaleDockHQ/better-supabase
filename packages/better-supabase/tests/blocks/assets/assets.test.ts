import { describe, expect, it } from "vitest";

import type { AssetLocationPatch } from "../../../src/blocks/assets/index.ts";

import {
  assetsBlock,
  assetsEvents,
  assetsBinding,
  createAssets,
} from "../../../src/blocks/assets/index.ts";

const AT = "2026-10-22T10:00:00Z";

const LOCATION = {
  id: "l1",
  organizationId: "org-1",
  parentId: "l0",
  kind: "building",
  name: "B1",
  code: "B1",
  address: { city: "Amsterdam" },
  latitude: 52.37,
  longitude: 4.89,
  area: { type: "MultiPolygon", coordinates: [] },
  metadata: { floors: 3 },
  archivedAt: null,
  createdAt: AT,
  updatedAt: AT,
};

const BARE_LOCATION = {
  id: "l0",
  organizationId: "org-1",
  parentId: null,
  kind: "site",
  name: "HQ",
  code: null,
  address: null,
  latitude: null,
  longitude: null,
  area: null,
  metadata: null,
  archivedAt: AT,
  createdAt: AT,
  updatedAt: AT,
};

const ASSET = {
  id: "a1",
  organizationId: "org-1",
  locationId: "l1",
  kind: "laptop",
  name: "MBP",
  tag: "TAG-1",
  serialNumber: "SN1",
  status: "active",
  assigneeType: "member",
  assigneeId: "u2",
  latitude: 52.371,
  longitude: 4.891,
  metadata: {},
  retiredAt: null,
  createdBy: "u1",
  createdAt: AT,
  updatedAt: AT,
};

const BARE_ASSET = {
  id: "a2",
  organizationId: "org-1",
  locationId: null,
  kind: "van",
  name: "Van",
  tag: null,
  serialNumber: null,
  status: "retired",
  assigneeType: "party",
  assigneeId: null,
  latitude: 52.1,
  longitude: null,
  metadata: null,
  retiredAt: AT,
  createdBy: null,
  createdAt: AT,
  updatedAt: AT,
};

const ASSIGNMENT = {
  id: "s1",
  assetId: "a1",
  assigneeType: "member",
  assigneeId: "u2",
  note: "for travel",
  assignedBy: "u1",
  assignedAt: AT,
  releasedAt: AT,
};

function fakeTransport(results: Record<string, unknown>) {
  const calls: [string, Record<string, unknown>][] = [];

  return {
    calls,
    transport: {
      call(
        _schema: string,
        fn: string,
        args: Readonly<Record<string, unknown>>,
      ) {
        calls.push([fn, { ...args }]);

        return Promise.resolve(results[fn]);
      },
    },
  };
}

describe("createAssets", () => {
  it("creates, reads and lists locations in the block's tenant", async () => {
    const fake = fakeTransport({
      create_asset_location: LOCATION,
      update_asset_location: BARE_LOCATION,
      archive_asset_location: BARE_LOCATION,
      get_asset_location: {
        ...LOCATION,
        path: [{ id: "l0", kind: "site", name: "HQ" }],
        locations: 2,
        assets: 5,
      },
      list_asset_locations: [LOCATION, BARE_LOCATION],
    });

    const assets = createAssets({ transport: fake.transport, tenant: "org-1" });

    const created = await assets
      .createLocation({
        kind: "building",
        name: "B1",
        parentId: "l0",
        code: "B1",
        address: { city: "Amsterdam" },
        point: { latitude: 52.37, longitude: 4.89 },
        area: { type: "Polygon", coordinates: [] },
        metadata: { floors: 3 },
      })
      .orThrow();

    expect(created).toMatchObject({
      id: "l1",
      parentId: "l0",
      code: "B1",
      point: { latitude: 52.37, longitude: 4.89 },
      area: { type: "MultiPolygon" },
      address: { city: "Amsterdam" },
    });
    expect(created.archivedAt).toBeUndefined();

    const bare = await assets.createLocation({ kind: "site", name: "HQ" });
    expect(bare.ok).toBe(true);

    const updated = await assets
      // SAFETY: an explicit `undefined` exercises the skip branch that
      // `exactOptionalPropertyTypes` rules out for typed callers.
      .updateLocation("l0", {
        name: "Head office",
        point: null,
        code: undefined,
      } as unknown as AssetLocationPatch)
      .orThrow();

    expect(updated).toMatchObject({ address: {}, metadata: {} });
    expect(updated.parentId).toBeUndefined();
    expect(updated.point).toBeUndefined();
    expect(updated.area).toBeUndefined();
    expect(updated.archivedAt?.toString()).toBe(AT);

    await assets
      .updateLocation("l0", { point: { latitude: 1, longitude: 2 } })
      .orThrow();
    await assets.archiveLocation("l0").orThrow();

    const detail = await assets.location("l1").orThrow();
    expect(detail).toMatchObject({
      path: [{ id: "l0", kind: "site", name: "HQ" }],
      locations: 2,
      assets: 5,
    });

    expect(await assets.locations().orThrow()).toHaveLength(2);
    await assets
      .locations({ parentId: "l0", includeArchived: true, pageSize: 10 })
      .orThrow();

    expect(fake.calls).toEqual([
      [
        "create_asset_location",
        {
          tenant: "org-1",
          kind: "building",
          name: "B1",
          parent_id: "l0",
          code: "B1",
          address: { city: "Amsterdam" },
          latitude: 52.37,
          longitude: 4.89,
          area: { type: "Polygon", coordinates: [] },
          metadata: { floors: 3 },
        },
      ],
      [
        "create_asset_location",
        {
          tenant: "org-1",
          kind: "site",
          name: "HQ",
          parent_id: null,
          code: null,
          address: null,
          latitude: null,
          longitude: null,
          area: null,
          metadata: null,
        },
      ],
      [
        "update_asset_location",
        {
          location_id: "l0",
          patch: { name: "Head office", latitude: null, longitude: null },
        },
      ],
      [
        "update_asset_location",
        { location_id: "l0", patch: { latitude: 1, longitude: 2 } },
      ],
      ["archive_asset_location", { location_id: "l0" }],
      ["get_asset_location", { location_id: "l1" }],
      [
        "list_asset_locations",
        {
          tenant: "org-1",
          parent_id: null,
          include_archived: false,
          page_size: null,
        },
      ],
      [
        "list_asset_locations",
        {
          tenant: "org-1",
          parent_id: "l0",
          include_archived: true,
          page_size: 10,
        },
      ],
    ]);
  });

  it("reads a location's counts as zero when they're missing", async () => {
    const fake = fakeTransport({
      get_asset_location: { ...LOCATION, path: [] },
    });

    const assets = createAssets({ transport: fake.transport, tenant: "org-1" });

    expect(await assets.location("l1").orThrow()).toMatchObject({
      path: [],
      locations: 0,
      assets: 0,
    });
  });

  it("creates, updates, lists and reads assets", async () => {
    const fake = fakeTransport({
      create_asset: ASSET,
      update_asset: BARE_ASSET,
      list_assets: [ASSET, BARE_ASSET],
      get_asset: {
        ...ASSET,
        locationPath: [{ id: "l1", kind: "building", name: "B1" }],
        links: {
          bookingResources: [{ id: "r1", name: "Room" }],
          workItems: [{ id: "w1", title: "Fix" }],
        },
      },
    });

    const assets = createAssets({ transport: fake.transport, tenant: "org-1" });

    const created = await assets
      .createAsset({
        kind: "laptop",
        name: "MBP",
        locationId: "l1",
        tag: "TAG-1",
        serialNumber: "SN1",
        point: { latitude: 52.371, longitude: 4.891 },
        metadata: { color: "grey" },
      })
      .orThrow();

    expect(created).toMatchObject({
      assignee: { type: "member", id: "u2" },
      point: { latitude: 52.371, longitude: 4.891 },
      createdBy: "u1",
      status: "active",
    });
    expect(created.retiredAt).toBeUndefined();

    await assets.createAsset({ kind: "van", name: "Van" }).orThrow();

    const retired = await assets
      .updateAsset("a2", { status: "retired" })
      .orThrow();

    expect(retired.assignee).toBeUndefined();
    expect(retired.point).toBeUndefined();
    expect(retired.locationId).toBeUndefined();
    expect(retired.retiredAt?.toString()).toBe(AT);

    expect(await assets.assets().orThrow()).toHaveLength(2);
    await assets
      .assets({
        locationId: "l1",
        includeSublocations: true,
        kind: "laptop",
        status: "active",
        assignee: { type: "member", id: "u2" },
        query: "mbp",
        before: Temporal.Instant.from(AT),
        pageSize: 20,
      })
      .orThrow();

    const detail = await assets.asset("a1").orThrow();
    expect(detail).toMatchObject({
      locationPath: [{ id: "l1", kind: "building", name: "B1" }],
      links: {
        bookingResources: [{ id: "r1", name: "Room" }],
        workItems: [{ id: "w1", title: "Fix" }],
      },
    });

    expect(fake.calls).toEqual([
      [
        "create_asset",
        {
          tenant: "org-1",
          kind: "laptop",
          name: "MBP",
          location_id: "l1",
          tag: "TAG-1",
          serial_number: "SN1",
          latitude: 52.371,
          longitude: 4.891,
          metadata: { color: "grey" },
        },
      ],
      [
        "create_asset",
        {
          tenant: "org-1",
          kind: "van",
          name: "Van",
          location_id: null,
          tag: null,
          serial_number: null,
          latitude: null,
          longitude: null,
          metadata: null,
        },
      ],
      ["update_asset", { asset_id: "a2", patch: { status: "retired" } }],
      [
        "list_assets",
        {
          tenant: "org-1",
          location_id: null,
          include_sublocations: false,
          kind: null,
          status: null,
          assignee_type: null,
          assignee_id: null,
          query: null,
          before: null,
          page_size: null,
        },
      ],
      [
        "list_assets",
        {
          tenant: "org-1",
          location_id: "l1",
          include_sublocations: true,
          kind: "laptop",
          status: "active",
          assignee_type: "member",
          assignee_id: "u2",
          query: "mbp",
          before: AT,
          page_size: 20,
        },
      ],
      ["get_asset", { asset_id: "a1" }],
    ]);
  });

  it("reads an asset without links as empty lists", async () => {
    const fake = fakeTransport({
      get_asset: { ...ASSET, locationPath: [], links: null },
    });

    const assets = createAssets({ transport: fake.transport, tenant: "org-1" });

    expect(await assets.asset("a1").orThrow()).toMatchObject({
      links: { bookingResources: [], workItems: [] },
    });
  });

  it("rejects an unknown asset status", async () => {
    const fake = fakeTransport({ get_asset: { ...ASSET, status: "lost" } });
    const assets = createAssets({ transport: fake.transport, tenant: "org-1" });

    expect((await assets.asset("a1")).ok).toBe(false);
  });

  it("assigns, releases and lists an asset's assignments", async () => {
    const fake = fakeTransport({
      assign_asset: ASSET,
      release_asset: BARE_ASSET,
      list_assets: [ASSET],
      asset_assignment_history: [
        ASSIGNMENT,
        { ...ASSIGNMENT, note: null, assignedBy: null, releasedAt: null },
      ],
    });

    const assets = createAssets({ transport: fake.transport });

    await assets
      .assign("a1", { type: "member", id: "u2" }, { note: "for travel" })
      .orThrow();
    await assets.assign("a1", { type: "party", id: "p1" }).orThrow();
    await assets.release("a1").orThrow();
    await assets.assignedTo({ type: "parties", id: "p1" }).orThrow();
    await assets
      .assignedTo({ type: "member", id: "u2" }, { pageSize: 5 })
      .orThrow();

    const history = await assets.assignments("a1").orThrow();
    expect(history[0]).toMatchObject({
      assignee: { type: "member", id: "u2" },
      note: "for travel",
      assignedBy: "u1",
    });
    expect(history[1]?.note).toBeUndefined();
    expect(history[1]?.releasedAt).toBeUndefined();
    await assets.assignments("a1", { pageSize: 3 }).orThrow();

    expect(fake.calls.map(([fn, args]) => [fn, args])).toEqual([
      [
        "assign_asset",
        {
          asset_id: "a1",
          assignee_type: "member",
          assignee_id: "u2",
          note: "for travel",
        },
      ],
      [
        "assign_asset",
        {
          asset_id: "a1",
          assignee_type: "party",
          assignee_id: "p1",
          note: null,
        },
      ],
      ["release_asset", { asset_id: "a1" }],
      [
        "list_assets",
        expect.objectContaining({
          tenant: null,
          assignee_type: "parties",
          assignee_id: "p1",
          page_size: null,
        }),
      ],
      [
        "list_assets",
        expect.objectContaining({
          tenant: null,
          assignee_type: "member",
          assignee_id: "u2",
          page_size: 5,
        }),
      ],
      ["asset_assignment_history", { asset_id: "a1", page_size: null }],
      ["asset_assignment_history", { asset_id: "a1", page_size: 3 }],
    ]);
  });

  it("finds assets and locations near a point and inside areas", async () => {
    const fake = fakeTransport({
      assets_near: {
        assets: [{ ...ASSET, distanceMeters: 130.5 }],
        locations: [{ ...LOCATION }],
      },
      asset_locations_at: [LOCATION],
      set_asset_link: null,
    });

    const assets = createAssets({ transport: fake.transport, tenant: "org-1" });

    const near = await assets
      .near({ latitude: 52.37, longitude: 4.89, radiusMeters: 1000 })
      .orThrow();

    expect(near.assets[0]?.distanceMeters).toBe(130.5);
    expect(near.locations[0]?.distanceMeters).toBe(0);

    await assets
      .near({
        latitude: 52.37,
        longitude: 4.89,
        radiusMeters: 50,
        kind: "laptop",
        pageSize: 5,
      })
      .orThrow();

    expect(
      await assets.locationsAt({ latitude: 52.37, longitude: 4.89 }).orThrow(),
    ).toHaveLength(1);

    expect(
      await assets.link({ type: "work_item", id: "w1" }, "a1").orThrow(),
    ).toEqual({ type: "work_item", id: "w1", assetId: "a1" });
    await assets.link({ type: "booking_resource", id: "r1" }, null).orThrow();

    expect(fake.calls).toEqual([
      [
        "assets_near",
        {
          tenant: "org-1",
          latitude: 52.37,
          longitude: 4.89,
          radius_meters: 1000,
          kind: null,
          page_size: null,
        },
      ],
      [
        "assets_near",
        {
          tenant: "org-1",
          latitude: 52.37,
          longitude: 4.89,
          radius_meters: 50,
          kind: "laptop",
          page_size: 5,
        },
      ],
      [
        "asset_locations_at",
        { tenant: "org-1", latitude: 52.37, longitude: 4.89 },
      ],
      [
        "set_asset_link",
        { target_type: "work_item", target_id: "w1", asset_id: "a1" },
      ],
      [
        "set_asset_link",
        { target_type: "booking_resource", target_id: "r1", asset_id: null },
      ],
    ]);
  });

  it("fails tenant-scoped calls without a tenant", async () => {
    const fake = fakeTransport({});
    const assets = createAssets({ transport: fake.transport });

    expect((await assets.assets()).ok).toBe(false);
    expect((await assets.locations()).ok).toBe(false);
    expect(
      (await assets.near({ latitude: 0, longitude: 0, radiusMeters: 1 })).ok,
    ).toBe(false);
    expect(fake.calls).toEqual([]);
  });
});

describe("assetsBinding", () => {
  it("loads the assets a record holds", async () => {
    const fake = fakeTransport({ list_assets: [ASSET] });
    const assets = createAssets({ transport: fake.transport });

    const rows = await assetsBinding
      .load(assets, { type: "parties", id: "p1" }, undefined)
      .orThrow();

    expect(rows).toHaveLength(1);
    expect(fake.calls[0]?.[1]).toMatchObject({
      assignee_type: "parties",
      assignee_id: "p1",
    });
  });

  it("is the block's record binding and listens to asset events", () => {
    expect(assetsBlock.record).toBe(assetsBinding);
    expect(assetsBinding.events).toEqual(["asset.*"]);
    expect(assetsEvents.types).toContain("asset.assigned");
  });
});
