import { CustomerList } from "../../components/customer-list";
import { bsb } from "../../lib/supabase/server";
import { customerColumns, customerList } from "../../lists";

/** Web only: runs on the server as the caller, through PostgREST and RLS. */
export const loader = bsb.loader(
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
