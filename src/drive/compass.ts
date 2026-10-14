/** The eight points of the compass, as an index 0 (north) .. 7 (north-west), for a heading in degrees from north. */
export function cardinalIndex(heading: number): number {
  const normalised = ((heading % 360) + 360) % 360;
  return Math.round(normalised / 45) % 8;
}
