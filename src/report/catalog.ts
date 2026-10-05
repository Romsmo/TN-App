/**
 * The hazard types a user can report. The library offers no list yet (wish for client-lib 1.2, docs/todo.md), so this
 * is the documented set from server/docs/api.md behind a small interface that a library method can replace.
 *
 * Camera types are not offered here: reporting speed cameras belongs to the camera handling (user switch, country
 * policy, legal notice), which comes with the drive mode.
 */
export interface ReportCatalog {
  types(): readonly string[];
}

export const interimCatalog: ReportCatalog = {
  types: () => ['traffic', 'accident', 'construction', 'ice', 'breakdown', 'obstacle'],
};
