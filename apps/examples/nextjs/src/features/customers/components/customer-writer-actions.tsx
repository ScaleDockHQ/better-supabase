import { can } from "@/features/user/user-permissions";
import { getSession } from "@/features/user/user-queries";

import { CreateCustomerDialog } from "./create-customer-form";

/** The "Add customer" button for `customers.write`. Render inside `<Suspense>`. */
export async function CustomerWriterActions() {
  const session = await getSession();
  return can(session, "customers.write") ? <CreateCustomerDialog /> : null;
}
