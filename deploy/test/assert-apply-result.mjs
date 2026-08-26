import { readFile } from "node:fs/promises";

const [responsePath, expectedKind, revisionKey, rawRevision] = process.argv.slice(2);
const expectedRevision = Number(rawRevision);
if (
  !responsePath ||
  !expectedKind ||
  !revisionKey ||
  !Number.isSafeInteger(expectedRevision)
) {
  throw new Error("Synthetic apply-result assertion configuration is invalid.");
}

const response = JSON.parse(await readFile(responsePath, "utf8"));
if (
  !response ||
  typeof response !== "object" ||
  response.kind !== expectedKind ||
  response[revisionKey] !== expectedRevision
) {
  throw new Error("Synthetic apply result did not match the expected outcome.");
}

process.stdout.write(`Synthetic ${expectedKind} result: yes\n`);
