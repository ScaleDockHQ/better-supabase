"use server";

import type { AssetInput } from "better-supabase/blocks/assets";

import { ok } from "better-supabase";
import * as v from "valibot";

import type { Mutable } from "@/lib/block-status-list";

import { refreshCaller } from "@/lib/refresh-caller";
import { bsb } from "@/lib/supabase/server";

import { ASSETS_TAG } from "./assets-cache";
import { ASSET_STATUSES } from "./assets-list";

const Id = v.pipe(v.string(), v.uuid());

const Text = (max: number) =>
  v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(max));

/** Adds an asset to the register. */
export const createAsset = bsb.action(
  {
    input: v.object({
      name: Text(200),
      kind: v.pipe(v.string(), v.trim(), v.regex(/^[a-z][a-z0-9_]{0,62}$/)),
      tag: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(60))),
      serialNumber: v.optional(v.pipe(v.string(), v.trim(), v.maxLength(80))),
    }),
    requireTenant: true,
    permission: "assets.manage",
  },
  async ({ name, kind, tag, serialNumber }, { db, auth }) => {
    const input: Mutable<AssetInput> = { name, kind };

    if (tag) {
      input.tag = tag;
    }

    if (serialNumber) {
      input.serialNumber = serialNumber;
    }

    const created = await db.assets.createAsset(input);

    if (!created.ok) {
      return created;
    }

    await refreshCaller(auth, [ASSETS_TAG]);

    return ok(created.data.id);
  },
);

/** Moves an asset between in service, in maintenance and retired. */
export const setAssetStatus = bsb.action(
  {
    input: v.object({ assetId: Id, status: v.picklist(ASSET_STATUSES) }),
    requireTenant: true,
    permission: "assets.manage",
  },
  async ({ assetId, status }, { db, auth }) => {
    const updated = await db.assets.updateAsset({ assetId, patch: { status } });

    if (!updated.ok) {
      return updated;
    }

    await refreshCaller(auth, [ASSETS_TAG]);

    return ok(updated.data.id);
  },
);

/** Ends the current assignment, so the asset is free again. */
export const releaseAsset = bsb.action(
  {
    input: v.object({ assetId: Id }),
    requireTenant: true,
    permission: "assets.assign",
  },
  async ({ assetId }, { db, auth }) => {
    const released = await db.assets.release(assetId);

    if (!released.ok) {
      return released;
    }

    await refreshCaller(auth, [ASSETS_TAG]);

    return ok(released.data.id);
  },
);
