// The shipped profile's own tool names, read from a real boot rather than
// guessed. A hardcoded list silently misses one and the substrate then lets a
// corpus package claim a seat the profile already owns.
import { pathToFileURL } from 'node:url'
import { writeFileSync } from 'node:fs'
const { boot } = await import(pathToFileURL('D:/codeproject/dsh-lab/packages/boot/app-boot/src/index.ts').href)
const ctx = await boot('dsh-e2e', process.argv[2])
const names = ctx.get('tools').schemas().map(t => t.name).sort()
writeFileSync(process.argv[3], JSON.stringify(names, null, 0))
console.log(`出厂工具 ${names.length} 个 -> ${process.argv[3]}`)
console.log(names.join(' '))
await ctx.fiber.dispose()
