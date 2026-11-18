#!/usr/bin/env node
// 静态校验接入基线用例池（7 列 JSON 数组）。退出码非 0 = 需自修。
import { readFileSync } from 'node:fs'

const file = process.argv[2]
if (!file) {
  console.error('用法: node case-lint.mjs <pool.json>')
  process.exit(2)
}

let cases
try {
  cases = JSON.parse(readFileSync(file, 'utf8'))
} catch (e) {
  console.error(`读取/解析失败: ${e.message}`)
  process.exit(2)
}
if (!Array.isArray(cases)) {
  console.error('pool.json 顶层必须是数组')
  process.exit(2)
}

const CODE = /^[A-Z][A-Z0-9_]{1,127}$/
const TAGS = new Set(['冒烟', '核心', '负向'])
const problems = []

for (const [i, c] of cases.entries()) {
  const at = `#${i} ${c.code ?? '(no code)'}`
  if (!CODE.test(c.code ?? '')) problems.push(`${at}: code 不合规 ${JSON.stringify(c.code)}`)
  const title = (c.name ?? '').trim()
  if (!title) problems.push(`${at}: name(标题) 为空`)
  else if ([...title].length > 20) problems.push(`${at}: 标题超 20 字 (${[...title].length})`)
  if (c.format !== 'prompt' && c.format !== undefined) problems.push(`${at}: format 应为 prompt，实际 ${c.format}`)
  const text = c.promptContent ?? ''
  if (!text.trim()) problems.push(`${at}: promptContent 为空`)
  if (!text.trimEnd().split('\n').at(-1)?.trimStart().startsWith('断言：')) {
    problems.push(`${at}: 未以「断言：」结尾`)
  }
  if (/https?:\/\//.test(text)) problems.push(`${at}: 含域名 http(s)://`)
  const tags = Array.isArray(c.tags) ? c.tags : String(c.tags ?? '').split(/[,，]/).map(s => s.trim()).filter(Boolean)
  if (!tags.length) problems.push(`${at}: 无分层标签`)
  for (const t of tags) if (!TAGS.has(t)) problems.push(`${at}: 未知标签 ${JSON.stringify(t)}`)
}

if (problems.length) {
  console.error(`发现 ${problems.length} 处问题：`)
  for (const p of problems) console.error('  - ' + p)
  process.exit(1)
}
console.log(`OK: ${cases.length} 条用例全部通过静态校验`)
