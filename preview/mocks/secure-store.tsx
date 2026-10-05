const memory = new Map<string, string>();
export function getItem(key: string): string | null {
  return memory.get(key) ?? null;
}
export function setItem(key: string, value: string): void {
  memory.set(key, value);
}
export async function deleteItemAsync(key: string): Promise<void> {
  memory.delete(key);
}
