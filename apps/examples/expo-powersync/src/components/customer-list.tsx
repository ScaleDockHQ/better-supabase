import { useLoaderData } from "expo-router";
import { Text } from "react-native";

import type { loader } from "../app/customers";

import { CustomerRows } from "./customer-rows";

/** Web: the page the server loader read. */
export function CustomerList() {
  const list = useLoaderData<typeof loader>();
  return (
    <CustomerRows
      rows={list.items}
      footer={<Text>{list.page.total} customers</Text>}
    />
  );
}
