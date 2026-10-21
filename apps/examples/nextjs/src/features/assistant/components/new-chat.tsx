import { connection } from "next/server";

import { durableAvailable } from "../assistant-server";
import { AssistantChat } from "./assistant-chat";

/**
 * Render inside `<Suspense>`: a chat with a fresh id per request; the server
 * creates it on the first message.
 */
export async function NewChat() {
  await connection();

  return (
    <AssistantChat
      // oxlint-disable-next-line react-doctor/rendering-hydration-mismatch-time -- a server component after `connection()`, so each request gets a fresh chat id on purpose
      id={crypto.randomUUID()}
      messages={[]}
      durableAvailable={durableAvailable()}
    />
  );
}
