import { configuration } from '../server.mjs';
import { writeFileSync, mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
const config = configuration(process.env, true);
mkdirSync('data', { recursive: true });
// Server-only generated file, gitignored. Never insert this key into a LocalScript.
writeFileSync('data/StudioConfig.lua', `return { baseUrl = ${JSON.stringify(config.publicUrl)}, apiKey = ${JSON.stringify(config.apiKey)} }\n`);
const built = spawnSync('rojo', ['build', 'studio/default.project.json', '-o', 'data/RewardCodesStudio.rbxl'], { stdio: 'inherit', shell: false });
if (built.error) throw built.error;
process.exitCode = built.status;
