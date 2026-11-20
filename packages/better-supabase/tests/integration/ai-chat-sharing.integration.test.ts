import { Pool } from "pg";
import { afterAll, describe, expect, it } from "vitest";

import { BlockSession, dbUrl, reachable } from "./block-session.ts";

const live = await reachable();

const text = (value: string) => [{ type: "text", text: value }];

async function setUp(s: BlockSession, modes?: readonly string[]) {
  await s.install(
    ["organizations", "outbox", "ai-chat"],
    modes === undefined
      ? {}
      : { modules: { "ai-chat": { options: { modes } } } },
  );
  const owner = await s.user("owner");
  const viewer = await s.user("viewer");
  const editor = await s.user("editor");
  const outsider = await s.user("outsider");

  const tenant = await s.organization(owner, {
    member1: viewer,
    member2: editor,
  });

  return { owner, viewer, editor, outsider, tenant };
}

describe.skipIf(!live)("ai-chat sharing and modes", () => {
  const pool = new Pool({ connectionString: dbUrl, max: 2 });

  afterAll(() => pool.end());

  it("serves the live link until it is rotated or revoked", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { owner, outsider, tenant } = await setUp(s);
      await s.as(owner);

      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Live" }],
      );

      await s.value("better_supabase.append_ai_user_message($1, $2)", [
        chat.id,
        { id: "u1", role: "user", parts: text("Hi") },
      ]);

      const link = await s.value<{ id: string; token: string }>(
        "better_supabase.create_ai_chat_link($1)",
        [chat.id],
      );

      // Anyone holding the token reads the active branch, signed in or not.
      await s.as("anon");
      expect(
        (
          await s.value<{ messages: { id: string }[] }>(
            "better_supabase.get_ai_chat_by_link($1)",
            [link.token],
          )
        ).messages.map((message) => message.id),
      ).toEqual(["u1"]);

      // The link follows the chat: a new message shows without a new token.
      await s.as(owner);
      await s.service();
      await s.value("better_supabase.save_ai_assistant_message($1, $2, 'u1')", [
        chat.id,
        { id: "a1", role: "assistant", parts: text("Hello") },
      ]);
      await s.as(outsider);
      expect(
        (
          await s.value<{ messages: { id: string }[] }>(
            "better_supabase.get_ai_chat_by_link($1)",
            [link.token],
          )
        ).messages.map((message) => message.id),
      ).toEqual(["u1", "a1"]);

      // Only the owner rotates, and the old token stops working.
      expect(
        await s.hint("better_supabase.rotate_ai_chat_link($1)", [chat.id]),
      ).toBe("AI_CHAT_NOT_FOUND");
      await s.as(owner);

      const rotated = await s.value<{ token: string }>(
        "better_supabase.rotate_ai_chat_link($1)",
        [chat.id],
      );

      expect(rotated.token).not.toBe(link.token);
      expect(
        await s.value("better_supabase.get_ai_chat_by_link($1)", [link.token]),
      ).toBeNull();

      expect(
        await s.value("better_supabase.revoke_ai_chat_link($1)", [chat.id]),
      ).toBe(true);
      expect(
        await s.value("better_supabase.get_ai_chat_by_link($1)", [
          rotated.token,
        ]),
      ).toBeNull();
    } finally {
      await s.close();
    }
  });

  it("limits what viewers, editors and outsiders do in a shared chat", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { owner, viewer, editor, outsider, tenant } = await setUp(s);
      await s.as(owner);

      const chat = await s.value<{ id: string }>(
        "better_supabase.create_ai_chat($1, $2)",
        [tenant, { title: "Team plan" }],
      );

      await s.value("better_supabase.add_ai_chat_participant($1, $2, $3)", [
        chat.id,
        viewer.id,
        "viewer",
      ]);
      await s.value("better_supabase.add_ai_chat_participant($1, $2, $3)", [
        chat.id,
        editor.id,
        "editor",
      ]);

      expect(
        (
          await s.value<{ user_id: string; role: string }[]>(
            "better_supabase.list_ai_chat_participants($1)",
            [chat.id],
          )
        )
          .map((participant) => participant.role)
          .toSorted(),
      ).toEqual(["editor", "owner", "viewer"]);

      // The owner may not be added as a participant of their own chat.
      expect(
        await s.hint("better_supabase.add_ai_chat_participant($1, $2)", [
          chat.id,
          owner.id,
        ]),
      ).toBe("AI_CHAT_INVALID");

      // Everyone who takes part reads the chat; an outsider does not.
      await s.as(viewer);
      expect(
        await s.value<{ title: string }>("better_supabase.get_ai_chat($1)", [
          chat.id,
        ]),
      ).toMatchObject({ title: "Team plan" });
      await s.as(outsider);
      expect(await s.hint("better_supabase.get_ai_chat($1)", [chat.id])).toBe(
        "AI_CHAT_NOT_FOUND",
      );

      // A viewer may not write; an editor may.
      await s.as(viewer);
      expect(
        await s.hint("better_supabase.append_ai_user_message($1, $2)", [
          chat.id,
          { id: "v1", role: "user", parts: text("Can I?") },
        ]),
      ).not.toBe("");
      await s.as(editor);
      expect(
        await s.value("better_supabase.append_ai_user_message($1, $2)", [
          chat.id,
          { id: "e1", role: "user", parts: text("Yes") },
        ]),
      ).toMatchObject({ message_id: "e1", created: true });

      // Only the owner shares, and a participant may leave.
      expect(
        await s.hint("better_supabase.add_ai_chat_participant($1, $2)", [
          chat.id,
          outsider.id,
        ]),
      ).toBe("AI_CHAT_NOT_FOUND");
      await s.as(viewer);
      expect(
        await s.value("better_supabase.remove_ai_chat_participant($1, $2)", [
          chat.id,
          viewer.id,
        ]),
      ).toBe(true);
      expect(await s.hint("better_supabase.get_ai_chat($1)", [chat.id])).toBe(
        "AI_CHAT_NOT_FOUND",
      );
    } finally {
      await s.close();
    }
  });

  it("rejects a mode outside options.modes", async () => {
    const s = await BlockSession.open(pool);

    try {
      const { owner, tenant } = await setUp(s, ["support", "research"]);
      await s.as(owner);

      expect(
        await s.value<{ mode: string }>(
          "better_supabase.create_ai_chat($1, $2)",
          [tenant, { title: "Ok", mode: "support" }],
        ),
      ).toMatchObject({ mode: "support" });
      await s.client.query("savepoint mode_check");
      await expect(
        s.value("better_supabase.create_ai_chat($1, $2)", [
          tenant,
          { title: "Bad", mode: "sales" },
        ]),
      ).rejects.toMatchObject({ code: "23514" });
      await s.client.query("rollback to savepoint mode_check");
    } finally {
      await s.close();
    }
  });
});
