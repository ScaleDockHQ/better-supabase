import { connection } from "next/server";

import { AssistantChat } from "./assistant-chat";

/**
 * Render inside `<Suspense>`: a chat with a fresh id per request; the
 * server creates it on the first message.
 */
export async function NewChat() {
  await connection();
  return <AssistantChat id={crypto.randomUUID()} messages={[]} />;
}
