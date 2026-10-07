import type { ReactElement } from "react";

import { memo } from "react";
import { FlatList, type ListRenderItem, Text, View } from "react-native";

interface Row {
  readonly id: string;
  readonly name: string;
  readonly status: string;
}

const CustomerRow = memo(function CustomerRow({ row }: { readonly row: Row }) {
  return (
    <View>
      <Text>{row.name}</Text>
      <Text>{row.status}</Text>
    </View>
  );
});

const renderRow: ListRenderItem<Row> = ({ item }) => <CustomerRow row={item} />;

const rowKey = (row: Row): string => row.id;

/** Watched lists rerun on every change: only rows whose data changed re-render. */
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
