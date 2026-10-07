/**
 * Turns player reports into the small public totals file.
 *
 * Pure: takes the reports (as plain objects), returns the totals. A game appears only once it has
 * `minReports` reports, so a single player's answer is never published on its own.
 */
export const MIN_REPORTS = 3;

export function aggregate(reports, minReports = MIN_REPORTS) {
  const byGame = new Map();
  for (const r of reports) {
    if (!Number.isInteger(r.appid) || r.appid <= 0 || typeof r.works !== "boolean" || !Number.isInteger(r.rating) || r.rating < 1 || r.rating > 5) continue;
    const g = byGame.get(r.appid) ?? { reports: 0, works: 0, ratingSum: 0 };
    g.reports += 1;
    g.works += r.works ? 1 : 0;
    g.ratingSum += r.rating;
    byGame.set(r.appid, g);
  }
  const games = {};
  for (const [appid, g] of [...byGame].sort((a, b) => a[0] - b[0])) {
    if (g.reports < minReports) continue;
    games[appid] = {
      reports: g.reports,
      works: g.works,
      worksShare: Math.round((g.works / g.reports) * 100) / 100,
      rating: Math.round((g.ratingSum / g.reports) * 10) / 10,
    };
  }
  return { generated: new Date().toISOString().slice(0, 10), minReports, games };
}
