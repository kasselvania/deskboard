import { timingSafeEqual } from "node:crypto";

import { APPLE_SOURCE_BEARER_TOKEN_PATTERN } from "./config.js";

export type FixedSecretComparator = (
  presented: Uint8Array,
  expected: Uint8Array,
) => boolean;

function nodeTimingSafeEqual(
  presented: Uint8Array,
  expected: Uint8Array,
): boolean {
  return timingSafeEqual(presented, expected);
}

export function authorizationMatchesConfiguredToken(
  authorization: string | string[] | undefined,
  configuredToken: string,
  compare: FixedSecretComparator = nodeTimingSafeEqual,
): boolean {
  if (
    typeof authorization !== "string" ||
    !APPLE_SOURCE_BEARER_TOKEN_PATTERN.test(configuredToken)
  ) {
    return false;
  }

  const match = /^Bearer ([0-9a-f]{64})$/.exec(authorization);
  if (!match?.[1]) {
    return false;
  }

  return compare(
    Buffer.from(match[1], "hex"),
    Buffer.from(configuredToken, "hex"),
  );
}
