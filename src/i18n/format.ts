import { getLanguage } from './index';

/** "1,5 MB" / "1.5 MB": decimal units, one decimal from 1 MB up. */
export function formatBytes(bytes: number): string {
  const language = getLanguage();
  const number = (value: number, digits: number) => new Intl.NumberFormat(language, { maximumFractionDigits: digits }).format(value);
  if (bytes < 1000) return `${number(bytes, 0)} B`;
  if (bytes < 1_000_000) return `${number(bytes / 1000, 0)} kB`;
  if (bytes < 1_000_000_000) return `${number(bytes / 1_000_000, 1)} MB`;
  return `${number(bytes / 1_000_000_000, 2)} GB`;
}

export function formatDateTime(value: Date | number | string): string {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return '?';
  return new Intl.DateTimeFormat(getLanguage(), { dateStyle: 'short', timeStyle: 'short' }).format(date);
}
