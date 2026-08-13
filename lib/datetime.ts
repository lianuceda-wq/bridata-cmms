export function localDateTimeToIso(value: string, offsetMinutes: number) {
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/)
  if (!match) throw new Error('Fecha/hora inválida.')

  const [, year, month, day, hour, minute, second = '0'] = match
  if (!Number.isFinite(offsetMinutes) || Math.abs(offsetMinutes) > 14 * 60) {
    throw new Error('Zona horaria inválida.')
  }

  const localAsUtc = Date.UTC(
    Number(year),
    Number(month) - 1,
    Number(day),
    Number(hour),
    Number(minute),
    Number(second),
  )

  return new Date(localAsUtc + offsetMinutes * 60_000).toISOString()
}
