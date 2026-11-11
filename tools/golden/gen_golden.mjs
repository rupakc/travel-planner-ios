#!/usr/bin/env node
// Golden fixtures: run the web's pure utils and record their outputs, so the Swift ports
// (Domain, Tasks 9-11) are tested for parity against the real JavaScript.
//
//   TZ=UTC node tools/golden/gen_golden.mjs <travel-planner checkout> [--check]
//
// For each tools/golden/cases/<name>.json:
//   {"module": "frontend/src/utils/<file>.js",
//    "setup": [{"module": "frontend/src/<file>.js", "fn": "<export>", "args": [...]}],   (optional, run first, awaited)
//    "cases": [{"name": "<case>", "fn": "<export>", "args": [...]}]}
// it loads the module from the checkout, calls fn(...args) and writes
// Packages/VoyagerKit/Tests/Fixtures/golden/<name>/<case>.json = {fn, args, output}.
// An arg {"$date": "<iso>"} becomes a Date; a Date in the output is written as {"$date": "<iso>"}.
// Objects are written with sorted keys. --check writes nothing and exits 1 on any difference
// (changed, missing or stale fixture).
//
// Modules are loaded through the checkout's own Vite (SSR module loader, no config file), the
// same transform the web's vitest uses: extensionless and directory imports, JSON imports and
// import.meta.glob (the i18n set-up) all work, and bare imports resolve from frontend/node_modules.
// Run `npm ci` in <checkout>/frontend first.

import { createRequire } from 'node:module'
import { existsSync } from 'node:fs'
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

process.env.TZ = process.env.TZ || 'UTC'

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const CASES_DIR = path.join(ROOT, 'tools', 'golden', 'cases')
const OUT_DIR = path.join(ROOT, 'Packages', 'VoyagerKit', 'Tests', 'Fixtures', 'golden')

function usage(message) {
  if (message) console.error(`gen_golden: ${message}`)
  console.error('usage: node tools/golden/gen_golden.mjs <travel-planner checkout> [--check]')
  process.exit(2)
}

const argv = process.argv.slice(2)
const check = argv.includes('--check')
const positional = argv.filter((a) => !a.startsWith('--'))
if (positional.length !== 1) usage()
const checkout = path.resolve(positional[0])
const frontend = path.join(checkout, 'frontend')
if (!existsSync(path.join(frontend, 'package.json'))) usage(`${checkout} is not a travel-planner checkout`)

// {"$date": iso} -> Date, recursively.
function reviveArg(value) {
  if (Array.isArray(value)) return value.map(reviveArg)
  if (value && typeof value === 'object') {
    const keys = Object.keys(value)
    if (keys.length === 1 && keys[0] === '$date') return new Date(value.$date)
    return Object.fromEntries(keys.map((k) => [k, reviveArg(value[k])]))
  }
  return value
}

// A JSON-safe, key-sorted copy: Date -> {"$date"}, undefined in arrays -> null,
// undefined properties and functions dropped, non-finite numbers -> null (as JSON.stringify).
function normalize(value) {
  if (value instanceof Date) return { $date: value.toISOString() }
  if (Array.isArray(value)) return value.map((v) => { const n = normalize(v); return n === undefined ? null : n })
  if (value instanceof Map) return normalize(Object.fromEntries(value))
  if (value instanceof Set) return normalize([...value])
  if (value && typeof value === 'object') {
    const out = {}
    for (const key of Object.keys(value).sort()) {
      const n = normalize(value[key])
      if (n !== undefined) out[key] = n
    }
    return out
  }
  if (typeof value === 'function' || typeof value === 'symbol') return undefined
  if (typeof value === 'number' && !Number.isFinite(value)) return null
  return value
}

const serialize = (value) => `${JSON.stringify(value, null, 2)}\n`

async function loadVite() {
  const require = createRequire(path.join(frontend, 'package.json'))
  let pkgPath
  try {
    pkgPath = require.resolve('vite/package.json')
  } catch {
    usage(`vite is not installed in ${frontend} (run npm ci there)`)
  }
  // The ESM build (`exports["."].import`), not the deprecated CJS one require() would pick.
  const pkg = JSON.parse(await readFile(pkgPath, 'utf8'))
  let entry = pkg.exports?.['.']?.import ?? 'dist/node/index.js'
  if (typeof entry === 'object') entry = entry.default
  return import(pathToFileURL(path.join(path.dirname(pkgPath), entry)).href)
}

async function main() {
  const caseFiles = existsSync(CASES_DIR)
    ? (await readdir(CASES_DIR)).filter((f) => f.endsWith('.json')).sort()
    : []
  if (caseFiles.length === 0) {
    console.log('gen_golden: no case files in tools/golden/cases; nothing to do')
    return 0
  }

  const { createServer } = await loadVite()
  const cacheDir = await mkdtemp(path.join(tmpdir(), 'gen-golden-vite-'))
  const server = await createServer({
    root: frontend,
    configFile: false,
    cacheDir,
    logLevel: 'error',
    appType: 'custom',
    server: { middlewareMode: true, hmr: false, watch: null },
    optimizeDeps: { noDiscovery: true, include: [] },
  })

  let differences = 0
  const expected = new Set()
  try {
    for (const file of caseFiles) {
      const name = path.basename(file, '.json')
      const spec = JSON.parse(await readFile(path.join(CASES_DIR, file), 'utf8'))
      if (typeof spec.module !== 'string' || !Array.isArray(spec.cases)) {
        throw new Error(`${file}: needs "module" (string) and "cases" (array)`)
      }
      const modulePath = path.join(checkout, spec.module)
      if (!existsSync(modulePath)) throw new Error(`${file}: ${spec.module} not found in the checkout`)
      // Optional set-up calls (e.g. initialising i18next), run before the cases in the same module graph.
      for (const step of spec.setup ?? []) {
        const stepPath = path.join(checkout, step.module)
        if (!existsSync(stepPath)) throw new Error(`${file}: setup module ${step.module} not found in the checkout`)
        const stepFn = (await server.ssrLoadModule(stepPath))[step.fn]
        if (typeof stepFn !== 'function') throw new Error(`${file}: setup ${step.module} exports no function ${step.fn}`)
        await stepFn(...reviveArg(step.args ?? []))
      }
      const mod = await server.ssrLoadModule(modulePath)
      const seen = new Set()
      for (const c of spec.cases) {
        if (!c.name || !/^[A-Za-z0-9_.-]+$/.test(c.name)) throw new Error(`${file}: bad case name ${JSON.stringify(c.name)}`)
        if (seen.has(c.name)) throw new Error(`${file}: duplicate case ${c.name}`)
        seen.add(c.name)
        const fn = mod[c.fn]
        if (typeof fn !== 'function') throw new Error(`${file}/${c.name}: ${spec.module} exports no function ${c.fn}`)
        const args = c.args ?? []
        const output = await fn(...reviveArg(args))
        const text = serialize(normalize({ fn: c.fn, args, output }))
        const target = path.join(OUT_DIR, name, `${c.name}.json`)
        expected.add(target)
        const current = existsSync(target) ? await readFile(target, 'utf8') : null
        if (current === text) continue
        if (check) {
          differences += 1
          console.error(`gen_golden: ${path.relative(ROOT, target)} ${current === null ? 'is missing' : 'differs'}`)
        } else {
          await mkdir(path.dirname(target), { recursive: true })
          await writeFile(target, text)
          console.log(`gen_golden: wrote ${path.relative(ROOT, target)}`)
        }
      }
    }

    // Fixtures whose case no longer exists.
    if (existsSync(OUT_DIR)) {
      for (const dir of await readdir(OUT_DIR, { withFileTypes: true })) {
        if (!dir.isDirectory()) continue
        for (const f of await readdir(path.join(OUT_DIR, dir.name))) {
          const target = path.join(OUT_DIR, dir.name, f)
          if (!f.endsWith('.json') || expected.has(target)) continue
          if (check) {
            differences += 1
            console.error(`gen_golden: ${path.relative(ROOT, target)} is stale (no such case)`)
          } else {
            await rm(target)
            console.log(`gen_golden: removed stale ${path.relative(ROOT, target)}`)
          }
        }
      }
    }
  } finally {
    await server.close()
    await rm(cacheDir, { recursive: true, force: true })
  }

  if (check && differences > 0) {
    console.error(`gen_golden: ${differences} fixture(s) out of date; run without --check and commit`)
    return 1
  }
  if (check) console.log(`gen_golden: ${expected.size} fixture(s) match`)
  return 0
}

main().then(
  (code) => process.exit(code),
  (err) => { console.error(`gen_golden: ${err.stack || err}`); process.exit(1) },
)
