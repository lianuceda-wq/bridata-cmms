export function rowsToCsv(rows: Record<string, unknown>[]) {
  if (rows.length === 0) return '\uFEFF'

  const headers = Array.from(new Set(rows.flatMap((row) => Object.keys(row))))
  const encode = (value: unknown) => {
    const text = value == null ? '' : typeof value === 'object' ? JSON.stringify(value) : String(value)
    return '"' + text.split('"').join('""') + '"'
  }

  const lines = [
    headers.map(encode).join(';'),
    ...rows.map((row) => headers.map((header) => encode(row[header])).join(';')),
  ]

  return '\uFEFF' + lines.join('\r\n')
}
