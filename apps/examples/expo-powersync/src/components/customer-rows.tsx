import type { ReactElement } from "react";
import type { ListRenderItem } from "react-native";

import { router } from "expo-router";
import { memo } from "react";
import { FlatList, Pressable, Text } from "react-native";

interface Row {
  readonly id: string;
  readonly name: string;
  readonly status: string;
}

function CustomerRowItem({ row }: { readonly row: Row }): ReactElement {
  return (
    <Pressable
      accessibilityRole="link"
      onPress={() => {
        router.push({
          pathname: "/customers/[id]",
          params: { id: row.id, name: row.name },
        });
      }}
    >
      <Text>{row.name}</Text>
      <Text>{row.status}</Text>
    </Pressable>
  );
}

const CustomerRow = memo(CustomerRowItem);

const renderRow: ListRenderItem<Row> = ({ item }) => <CustomerRow row={item} />;

const rowKey = (row: Row): string => row.id;

/**
 * One row per customer; `memo` skips a row whose props didn't change between
 * two renders of the page.
 */
export function CustomerRows({
  rows,
  footer,
}: {
  readonly rows: readonly Row[];
  readonly footer: ReactElement;
}) {
  return (
    <FlatList
      data={rows}
      keyExtractor={rowKey}
      renderItem={renderRow}
      ListFooterComponent={footer}
      contentInsetAdjustmentBehavior="automatic"
    />
  );
}
