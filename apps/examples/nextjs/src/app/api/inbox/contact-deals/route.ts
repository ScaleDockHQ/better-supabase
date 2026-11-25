import { getContactDeals } from "../../../../features/inbox/contact-deals";
import { bsb } from "../../../../lib/supabase/server";

/**
 * `GET /api/inbox/contact-deals?conversation=&locale=`: the open deals that
 * name the conversation's contact. The context pane loads it after the thread
 * paints, so the inbox page bundles no deals block.
 */
export const GET = bsb.route(async (request, { db }) => {
  const id = request.nextUrl.searchParams.get("conversation");

  if (id === null || !/^[0-9a-f-]{36}$/u.test(id)) {
    return Response.json({ issues: [] }, { status: 400 });
  }

  const conversation = await db.inbox.conversations.getConversation(id);

  if (!conversation.ok) {
    return Response.json(
      { error: conversation.error.code },
      { status: conversation.error.code === "not_found" ? 404 : 500 },
    );
  }

  const deals = await getContactDeals(
    db,
    conversation.data.contactId,
    request.nextUrl.searchParams.get("locale") ?? "en",
  );

  return Response.json({ deals });
});
