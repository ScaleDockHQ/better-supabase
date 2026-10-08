"use server";

import { dbError, err, ok } from "better-supabase";
import { refresh } from "next/cache";
import * as v from "valibot";

import { blocks } from "@/lib/blocks";
import { avatars } from "@/lib/buckets";
import { bs } from "@/lib/supabase/server";

/**
 * Call after the browser client signs in or out. `refresh()` from a Server
 * Action clears the client router cache, including every private session
 * read, so the next render sees the new user.
 */
// oxlint-disable-next-line typescript/require-await -- Next.js requires Server Actions to be async
export async function sessionChanged(): Promise<void> {
  refresh();
}

/** The caller's name in the profiles SQL module (`public.update_my_profile`). */
export const updateProfile = bs.action(
  {
    input: v.object({
      fullName: v.pipe(v.string(), v.trim(), v.minLength(1), v.maxLength(120)),
    }),
  },
  async ({ fullName }, { auth, db }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to change your profile"));
    }
    const updated = await db.$rpc("update_my_profile", { full_name: fullName });
    if (!updated.ok) return updated;
    refresh();
    return ok(true);
  },
);

const AVATAR_EXTENSIONS = new Map([
  ["image/png", "png"],
  ["image/jpeg", "jpg"],
  ["image/webp", "webp"],
  ["image/gif", "gif"],
  ["image/avif", "avif"],
]);

/**
 * Uploads a new avatar under the caller's id, points the profile at its
 * path (`public.set_my_avatar_path`), then removes the previous object.
 */
export const uploadAvatar = bs.action(
  {
    input: v.object({
      avatar: v.pipe(
        v.instance(File),
        v.check((file) => file.size > 0, "Pick a file"),
      ),
    }),
  },
  async ({ avatar }, { auth, db, supabase }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to change your avatar"));
    }
    const ext = AVATAR_EXTENSIONS.get(avatar.type);
    if (!ext) {
      return err(
        dbError("invalid_input", "Use a PNG, JPEG, WebP, GIF or AVIF image", {
          status: 415,
        }),
      );
    }
    const profile = await db.$rpc("my_profile");
    if (!profile.ok) return profile;
    const replaced = await avatars
      .connect(supabase)
      .replace(
        { userId: auth.user.id, version: crypto.randomUUID(), ext },
        avatar,
        {
          contentType: avatar.type,
          previous: profile.data[0]?.avatarPath ?? null,
          commit: (path) =>
            db.$rpc("set_my_avatar_path", { avatar_path: path }),
        },
      );
    if (replaced.ok) refresh();
    return replaced;
  },
);

/** A user setting from `settings-definition.ts` (the settings SQL module). */
export const setWeeklyDigest = bs.action(
  { input: v.object({ enabled: v.boolean() }) },
  async ({ enabled }, { supabase }) => {
    const saved = await blocks(supabase).settings.user.set(
      "weeklyDigest",
      enabled,
    );
    if (saved.ok) refresh();
    return saved;
  },
);

/**
 * Deletes the signed-in user, their avatars and their cached session;
 * notifications cascade. Customer logos belong to the organization, so that
 * bucket is left alone. Needs a verified second factor in this session.
 */
export const deleteMyAccount = bs.action(
  { aal: "aal2" },
  async (_input, { auth }) => {
    if (auth.kind !== "user") {
      return err(dbError("unauthorized", "Sign in to delete your account"));
    }
    return bs.deleteAccount(auth.user.id, {
      buckets: [avatars],
      cascades: ["notifications"],
    });
  },
);
