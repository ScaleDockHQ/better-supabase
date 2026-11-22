import { httpBasic, localDev } from "eve/channels/auth";
import { eveChannel } from "eve/channels/eve";

// `eve dev` accepts the local developer; a built server (`eve start`) needs the basic credential.
export default eveChannel({
  auth: [
    localDev(),
    httpBasic({ username: "eve-world", password: "eve-world-password" }),
  ],
});
