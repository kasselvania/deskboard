import { readFile } from "node:fs/promises";

const [indexPath] = process.argv.slice(2);
if (!indexPath) {
  throw new Error("Static index path is required.");
}

const index = await readFile(indexPath, "utf8");
const match = index.match(/(?:src|href)="(\/assets\/[^"]+)"/u);
if (!match?.[1] || !/\.[a-z0-9]+$/u.test(match[1])) {
  throw new Error("A hashed production asset was not found.");
}
process.stdout.write(match[1]);
