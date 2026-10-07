import { test as setup } from "@playwright/test";

import { signIn } from "./nav";
import { users } from "./users";

for (const [name, user] of Object.entries(users)) {
  setup(`sign in as ${name}`, async ({ page }) => {
    await signIn(page, user.email);
    await page.context().storageState({ path: user.storageState });
  });
}
