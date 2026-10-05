import { CustomerList } from "../../components/customer-list";
import { bs } from "../../lib/supabase/server";
import { customerColumns, customerList } from "../../lists";

/** Web only: runs on the server as the caller, through PostgREST and RLS. */
export const loader = bs.loader(
  async ({ db }, _params, request) => {
    const query =
      customerList.parse(new URL(request.url).searchParams).value ??
      customerList.defaults;
    return customerList.run(db, query, { select: customerColumns }).orThrow();
  },
  { allow: ["user"] },
);

export default function CustomersScreen() {
  return <CustomerList />;
}
