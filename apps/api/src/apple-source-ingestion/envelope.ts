import {
  appleSourceSnapshotV1Schema,
  type AppleSourceSnapshotV1,
} from "@deskboard/contracts";

export interface AppleSourceIngestionEnvelope {
  sourceRevision: number;
  snapshot: AppleSourceSnapshotV1;
}

export function parseAppleSourceIngestionEnvelope(
  input: unknown,
): AppleSourceIngestionEnvelope | undefined {
  if (input === null || typeof input !== "object" || Array.isArray(input)) {
    return undefined;
  }

  const candidate = input as Record<string, unknown>;
  const keys = Object.keys(candidate);
  if (
    keys.length !== 2 ||
    !Object.hasOwn(candidate, "sourceRevision") ||
    !Object.hasOwn(candidate, "snapshot")
  ) {
    return undefined;
  }
  if (
    typeof candidate.sourceRevision !== "number" ||
    !Number.isSafeInteger(candidate.sourceRevision) ||
    candidate.sourceRevision <= 0
  ) {
    return undefined;
  }

  const snapshot = appleSourceSnapshotV1Schema.safeParse(candidate.snapshot);
  if (!snapshot.success) {
    return undefined;
  }

  return {
    sourceRevision: candidate.sourceRevision,
    snapshot: snapshot.data,
  };
}
