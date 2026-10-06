// Runs negoto-design.js against the OpenPencil Figma plugin API, lays out every
// auto-layout frame, and writes Negoto.fig (the CLI's `eval` skips the layout pass).
import { readFile, writeFile } from 'node:fs/promises'

import { FigmaAPI } from '@open-pencil/core/figma-api'
import { BUILTIN_IO_FORMATS, IORegistry } from '@open-pencil/core/io'
import { computeAllLayouts } from '@open-pencil/core/layout'

const [base, out] = process.argv.slice(2)
const io = new IORegistry(BUILTIN_IO_FORMATS)
const { graph } = await io.readDocument({ name: base, data: new Uint8Array(await readFile(base)) })
const figma = new FigmaAPI(graph)
const code = await readFile(new URL('./negoto-design.js', import.meta.url), 'utf-8')
const AsyncFunction = Object.getPrototypeOf(async () => undefined).constructor
console.log(await new AsyncFunction('figma', code)(figma))
computeAllLayouts(graph)
await writeFile(out, (await io.writeDocument('fig', graph)).data as Uint8Array)
console.log(`Written to ${out}`)
