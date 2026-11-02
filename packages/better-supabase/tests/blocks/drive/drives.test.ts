import { describe, expect, it } from "vitest";

import { createDrive } from "../../../src/blocks/drive/index.ts";

function transport(results: Record<string, (args: unknown) => unknown>) {
  const calls: [string, string, unknown][] = [];

  return {
    calls,
    call(schema: string, fn: string, args: unknown) {
      calls.push([schema, fn, args]);
      const result = results[fn];

      if (!result) {
        return Promise.reject(new Error(`unexpected ${fn}`));
      }

      return Promise.resolve(result(args));
    },
  };
}

const DRIVE = {
  id: "d1",
  organizationId: "o",
  name: "Team files",
  kind: "shared",
  ownerId: "u1",
  connectionId: null,
  createdBy: "u1",
  createdAt: "2026-10-01T00:00:00Z",
  updatedAt: null,
  role: "owner",
  readOnly: false,
};

const DRIVE_GRANT = {
  id: "dg1",
  driveId: "d1",
  principalType: "team",
  principalId: "t1",
  role: "editor",
  expiresAt: null,
};

const CONNECTION = {
  id: "c1",
  organizationId: "o",
  userId: "u1",
  provider: "google-drive",
  name: "Drive",
  status: "connected",
  syncCursor: "cursor",
  lastSyncedAt: null,
  lastSyncError: null,
  createdAt: "2026-10-01T00:00:00Z",
  updatedAt: null,
};

const NODE = {
  id: "n1",
  organizationId: "o",
  parentId: "f1",
  kind: "file",
  name: "plan.pdf",
  rank: null,
  createdBy: "u1",
  createdAt: "2026-10-01T00:00:00Z",
  updatedAt: null,
  deletedAt: null,
  driveId: "d1",
  source: "google-drive",
  externalId: "ext-1",
  externalMetadata: { webViewLink: "https://example.test/ext-1" },
  legalHoldUntil: "2026-12-01T00:00:00Z",
  readOnly: true,
  held: true,
};

describe("drive drives and connections", () => {
  it("lists, creates, renames, shares and deletes drives", async () => {
    const fake = transport({
      drive_list_drives: () => [DRIVE],
      drive_get_drive: () => DRIVE,
      drive_create_drive: (args) => ({
        ...DRIVE,
        name: (args as { name: string }).name,
        kind: (args as { kind: string | null }).kind ?? "shared",
        connectionId: (args as { connection: string | null }).connection,
      }),
      drive_rename_drive: () => ({ ...DRIVE, name: "Archive" }),
      drive_delete_drive: () => true,
      drive_share_drive: () => DRIVE_GRANT,
      drive_unshare_drive: () => true,
      drive_grants_for_drive: () => [DRIVE_GRANT],
    });

    const drive = createDrive({ transport: fake });

    const [listed] = await drive
      .drives({ organizationId: "o", options: { pageSize: 5, skip: 5 } })
      .orThrow();

    expect(listed).toMatchObject({ id: "d1", role: "owner", readOnly: false });
    expect(listed?.connectionId).toBeUndefined();
    expect(listed?.updatedAt).toBeUndefined();
    expect((await drive.drive("d1").orThrow()).name).toBe("Team files");

    const created = await drive
      .createDrive({
        organizationId: "o",
        drive: { name: "Team files", kind: "shared", ownerId: "u2" },
      })
      .orThrow();

    expect(created.name).toBe("Team files");

    const mirrored = await drive
      .createDrive({
        organizationId: "o",
        drive: { name: "Mirror", connectionId: "c1" },
      })
      .orThrow();

    expect(mirrored.kind).toBe("shared");
    expect(mirrored.connectionId).toBe("c1");

    expect(
      (await drive.renameDrive({ id: "d1", name: "Archive" }).orThrow()).name,
    ).toBe("Archive");
    expect(await drive.deleteDrive("d1").orThrow()).toBe(true);

    const shared = await drive
      .shareDrive({
        id: "d1",
        principal: { type: "team", id: "t1" },
        role: "editor",
        expiresAt: Temporal.Instant.from("2026-11-01T00:00:00Z"),
      })
      .orThrow();

    expect(shared).toMatchObject({
      driveId: "d1",
      principal: { type: "team", id: "t1" },
    });
    expect(shared.expiresAt).toBeUndefined();
    expect(
      await drive
        .unshareDrive({ id: "d1", principal: { type: "team", id: "t1" } })
        .orThrow(),
    ).toBe(true);

    const [grant] = await drive.driveGrants("d1").orThrow();
    expect(grant?.role).toBe("editor");

    expect(fake.calls.map(([, fn, args]) => [fn, args])).toEqual([
      ["drive_list_drives", { tenant: "o", page_size: 5, skip: 5 }],
      ["drive_get_drive", { drive: "d1" }],
      [
        "drive_create_drive",
        {
          tenant: "o",
          name: "Team files",
          kind: "shared",
          owner: "u2",
          connection: null,
        },
      ],
      [
        "drive_create_drive",
        {
          tenant: "o",
          name: "Mirror",
          kind: null,
          owner: null,
          connection: "c1",
        },
      ],
      ["drive_rename_drive", { drive: "d1", name: "Archive" }],
      ["drive_delete_drive", { drive: "d1" }],
      [
        "drive_share_drive",
        {
          drive: "d1",
          principal_type: "team",
          principal_id: "t1",
          role: "editor",
          expires_at: "2026-11-01T00:00:00Z",
        },
      ],
      [
        "drive_unshare_drive",
        { drive: "d1", principal_type: "team", principal_id: "t1" },
      ],
      ["drive_grants_for_drive", { drive: "d1" }],
    ]);
  });

  it("lists, connects and disconnects external accounts", async () => {
    const fake = transport({
      drive_list_connections: () => [CONNECTION],
      drive_connect: () => CONNECTION,
      drive_disconnect: () => true,
    });

    const drive = createDrive({ transport: fake });

    const [connection] = await drive
      .connections({ organizationId: "o", pageSize: 10 })
      .orThrow();

    expect(connection).toMatchObject({
      id: "c1",
      provider: "google-drive",
      status: "connected",
    });
    expect(connection?.lastSyncedAt).toBeUndefined();
    expect(connection?.updatedAt).toBeUndefined();
    expect(
      (
        await drive
          .connect({
            organizationId: "o",
            provider: "google-drive",
            name: "Drive",
          })
          .orThrow()
      ).syncCursor,
    ).toBe("cursor");
    expect(await drive.disconnect("c1").orThrow()).toBe(true);

    expect(fake.calls.map(([, fn, args]) => [fn, args])).toEqual([
      ["drive_list_connections", { tenant: "o", page_size: 10 }],
      [
        "drive_connect",
        { tenant: "o", provider: "google-drive", name: "Drive" },
      ],
      ["drive_disconnect", { connection: "c1" }],
    ]);
  });

  it("places and releases a legal hold", async () => {
    const fake = transport({
      drive_hold: () => NODE,
      drive_release_hold: () => ({
        ...NODE,
        legalHoldUntil: null,
        held: false,
      }),
    });

    const drive = createDrive({ transport: fake });

    const held = await drive
      .hold({ id: "n1", until: Temporal.Instant.from("2026-12-01T00:00:00Z") })
      .orThrow();

    expect(held.legalHoldUntil?.toString()).toBe("2026-12-01T00:00:00Z");
    expect(held.held).toBe(true);
    expect(held.readOnly).toBe(true);
    expect(held.driveId).toBe("d1");
    expect(held.source).toBe("google-drive");
    expect(held.externalId).toBe("ext-1");
    expect(held.externalMetadata).toEqual({
      webViewLink: "https://example.test/ext-1",
    });

    const released = await drive.releaseHold("n1").orThrow();
    expect(released.legalHoldUntil).toBeUndefined();
    expect(released.held).toBe(false);

    expect(fake.calls.map(([, fn, args]) => [fn, args])).toEqual([
      ["drive_hold", { node: "n1", until: "2026-12-01T00:00:00Z" }],
      ["drive_release_hold", { node: "n1" }],
    ]);
  });

  it("defaults an internal, writable node", async () => {
    const fake = transport({
      drive_get: () => ({
        ...NODE,
        source: null,
        externalId: null,
        externalMetadata: null,
        legalHoldUntil: null,
        readOnly: null,
        held: null,
      }),
    });

    const node = await createDrive({ transport: fake }).get("n1").orThrow();

    expect(node.source).toBe("internal");
    expect(node.externalId).toBeUndefined();
    expect(node.externalMetadata).toBeUndefined();
    expect(node.legalHoldUntil).toBeUndefined();
    expect(node.readOnly).toBe(false);
    expect(node.held).toBe(false);
  });
});
