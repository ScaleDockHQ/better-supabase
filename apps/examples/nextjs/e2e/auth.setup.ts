import { expect, test as setup } from "@playwright/test";

import { password, users } from "./users";

for (const [name, user] of Object.entries(users)) {
  setup(`sign in as ${name}`, async ({ page }) => {
    await page.goto("/login");
    await page.getByPlaceholder("Email").fill(user.email);
    await page.getByPlaceholder("Password").fill(password);
    await page.getByRole("button", { name: "Sign in" }).click();
    await page.waitForURL((url) => url.pathname === "/");
    await expect(
      page.getByRole("heading", { name: "Dashboard" }),
    ).toBeVisible();
    await page.context().storageState({ path: user.storageState });
  });
}
