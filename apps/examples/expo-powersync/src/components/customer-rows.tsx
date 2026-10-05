import type { ReactElement } from "react";

import { FlatList, Text, View } from "react-native";

interface Row {
  readonly id: string;
  readonly name: string;
  readonly status: string;
}

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
      keyExtractor={(row) => row.id}
      renderItem={({ item }) => (
        <View>
          <Text>{item.name}</Text>
          <Text>{item.status}</Text>
        </View>
      )}
      ListFooterComponent={footer}
    />
  );
}
