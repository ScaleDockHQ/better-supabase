import { initBotId } from "botid/client/core";

// Ask AI is the only route that spends money per request.
initBotId({ protect: [{ path: "/docs/api/chat", method: "POST" }] });
