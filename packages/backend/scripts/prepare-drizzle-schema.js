import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.resolve(__dirname, '..');
const sourceDir = path.join(backendRoot, 'src', 'schemas');
const targetDir = path.join(backendRoot, '.drizzle-schema');

function transformSchemaSource(source) {
  return source
    // Drop type-only imports, including multiline blocks.
    .replace(/^\s*import\s+type\s+[\s\S]*?;\r?\n/gm, '')
    // Drop exported TS-only aliases.
    .replace(/^\s*export\s+type\s+.*;\r?\n/gm, '')
    // Rewrite local TS imports/exports to JS files for the generated mirror.
    .replace(/(\.\/[^'"`]+)\.ts(?=['"`])/g, '$1.js');
}

async function main() {
  await fs.rm(targetDir, { recursive: true, force: true });
  await fs.mkdir(targetDir, { recursive: true });

  const entries = await fs.readdir(sourceDir, { withFileTypes: true });
  const schemaFiles = entries.filter((entry) => entry.isFile() && entry.name.endsWith('.ts'));

  for (const entry of schemaFiles) {
    const sourcePath = path.join(sourceDir, entry.name);
    const targetPath = path.join(targetDir, entry.name.replace(/\.ts$/, '.js'));
    const source = await fs.readFile(sourcePath, 'utf8');
    await fs.writeFile(targetPath, transformSchemaSource(source), 'utf8');
  }

  console.log(`[drizzle:schema] Prepared JS schema mirror in ${targetDir}`);
}

await main();
