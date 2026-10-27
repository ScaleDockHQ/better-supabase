import { getPermissions } from "@/features/user/permission-snapshot";
import { can } from "@/features/user/user-permissions";

import { CreateCustomerDialog } from "./create-customer-form";

/** The "Add customer" button for `customers.write`. Render inside `<Suspense>`. */
export async function CustomerWriterActions() {
  const permissions = await getPermissions();

  return can(permissions, "customers.write") ? <CreateCustomerDialog /> : null;
}
