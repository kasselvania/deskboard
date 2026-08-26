import { readFile, writeFile } from "node:fs/promises";

const [method, path, responsePath, headersPath, bodyPath, authenticated] =
  process.argv.slice(2);

if (
  !["GET", "POST"].includes(method) ||
  !path?.startsWith("/") ||
  !responsePath ||
  !headersPath
) {
  throw new Error("Synthetic proxy request configuration is invalid.");
}

const headers = {};
if (bodyPath !== "-") {
  headers["content-type"] = "application/json";
}
if (authenticated === "authenticated") {
  const tokenFile = process.env.DESKBOARD_SYNTHETIC_TOKEN_FILE;
  if (!tokenFile) {
    throw new Error("Synthetic proxy token is missing.");
  }
  const token = await readFile(tokenFile, "utf8");
  if (!/^[0-9a-f]{64}$/.test(token)) {
    throw new Error("Synthetic proxy token is invalid.");
  }
  headers.authorization = `Bearer ${token}`;
}

const response = await fetch(`http://private-proxy:8080${path}`, {
  method,
  headers,
  body: bodyPath === "-" ? undefined : await readFile(bodyPath),
  redirect: "manual",
});

await writeFile(responsePath, Buffer.from(await response.arrayBuffer()), {
  mode: 0o600,
});
await writeFile(
  headersPath,
  [...response.headers.entries()]
    .map(([name, value]) => `${name}: ${value}\n`)
    .join(""),
  { mode: 0o600 },
);
process.stdout.write(`${response.status}`);
