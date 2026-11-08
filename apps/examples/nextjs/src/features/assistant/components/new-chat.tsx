import { io } from "next/cache";

import { durableAvailable } from "../assistant-server";
import { AssistantChatLazy } from "./assistant-chat-lazy";

// skeleton: renders from props and translations, so nothing of its own suspends
/**
 * Render inside `<Suspense>`: a chat with a fresh id per request; the server
 * creates it on the first message.
 */
export async function NewChat() {
  await io();

  return (
    <AssistantChatLazy
      // oxlint-disable-next-line react-doctor/rendering-hydration-mismatch-time -- a server component after `io()`, so each request gets a fresh chat id on purpose
      id={crypto.randomUUID()}
      messages={[]}
      durableAvailable={durableAvailable()}
    />
  );
}
