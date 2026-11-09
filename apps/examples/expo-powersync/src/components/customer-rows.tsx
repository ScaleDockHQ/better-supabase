import type { ReactElement } from "react";

import { FlashList } from "@shopify/flash-list";
import { router } from "expo-router";
import { memo } from "react";
import { Pressable, Text } from "react-native";

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

const rowKey = (row: Row): string => row.id;

/**
 * One row per customer. The list draws the rows on screen and asks for the next
 * page as the reader nears the end.
 */
export function CustomerRows({
  rows,
  footer,
  onEndReached,
}: {
  readonly rows: readonly Row[];
  readonly footer: ReactElement;
  readonly onEndReached?: (() => void) | undefined;
}) {
  return (
    <FlashList
      data={rows}
      keyExtractor={rowKey}
      renderItem={({ item }) => <CustomerRow row={item} />}
      ListFooterComponent={footer}
      onEndReached={onEndReached}
      onEndReachedThreshold={0.5}
    />
  );
}
