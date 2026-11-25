// Downloads the pinned docpack release (MIT, github.com/xskyofx-lang/docpack)
// into windows/binaries/docpack.exe, where tauri.conf.json bundles it.
// The download is checked against the SHA-256 pinned in scripts/docpack.json:
// a mismatch deletes the file and fails the build. To move to a newer docpack,
// change that file by hand after reading the new release's SHA256SUMS.txt.

import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const pin = JSON.parse(readFileSync(join(root, "scripts", "docpack.json"), "utf8"));
const dest = join(root, "binaries", "docpack.exe");

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");

if (existsSync(dest) && sha256(readFileSync(dest)) === pin.sha256) {
  console.log(`docpack ${pin.version} already in place`);
  process.exit(0);
}

console.log(`Downloading docpack ${pin.version}…`);
const res = await fetch(pin.url);
if (!res.ok) {
  console.error(`Could not download docpack: HTTP ${res.status}`);
  process.exit(1);
}
const bytes = Buffer.from(await res.arrayBuffer());
const got = sha256(bytes);
if (got !== pin.sha256) {
  rmSync(dest, { force: true });
  console.error(`docpack checksum mismatch: expected ${pin.sha256}, got ${got}`);
  process.exit(1);
}
mkdirSync(dirname(dest), { recursive: true });
writeFileSync(dest, bytes);
console.log(`docpack ${pin.version} ready (${(bytes.length / 1024 / 1024).toFixed(1)} MB)`);
