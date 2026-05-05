// OpenStreetMap Nominatim — used to surface POIs (golf courses, restaurants,
// parks, businesses) that aren't in Immich's local geodata_places table.
// Public endpoint fair-use: ≤ 1 req/s, set a meaningful Referer/User-Agent.
// In the browser User-Agent is locked, but Referer is set automatically by the
// origin and that's enough for the public endpoint's typical use.

export type NominatimPlace = {
  /** Latitude (decimal degrees, WGS84) */
  lat: number;
  /** Longitude (decimal degrees, WGS84) */
  lng: number;
  /** Short label, e.g. "Alhambra Golf Course" */
  name: string;
  /** Full address, e.g. "Alhambra Golf Course, Almonte Avenue, Alhambra, …" */
  displayName: string;
  /** OSM class (e.g. "leisure"), useful for sorting/filtering */
  category: string;
  /** OSM type (e.g. "golf_course") */
  type: string;
};

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';

export const searchNominatim = async (query: string, signal?: AbortSignal): Promise<NominatimPlace[]> => {
  const trimmed = query.trim();
  if (trimmed.length === 0) {
    return [];
  }

  const url = new URL(NOMINATIM_URL);
  url.searchParams.set('q', trimmed);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('limit', '8');
  url.searchParams.set('addressdetails', '0');

  const response = await fetch(url, { signal, headers: { Accept: 'application/json' } });
  if (!response.ok) {
    throw new Error(`Nominatim search failed (${response.status})`);
  }

  const data = (await response.json()) as Array<{
    lat: string;
    lon: string;
    name?: string;
    display_name: string;
    category?: string;
    type?: string;
  }>;

  return data
    .map((item) => {
      const lat = Number.parseFloat(item.lat);
      const lng = Number.parseFloat(item.lon);
      if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
        return null;
      }
      // Some results don't expose a short `name`; fall back to the first segment of display_name.
      const name = item.name && item.name.length > 0 ? item.name : item.display_name.split(',')[0].trim();
      return {
        lat,
        lng,
        name,
        displayName: item.display_name,
        category: item.category ?? '',
        type: item.type ?? '',
      } satisfies NominatimPlace;
    })
    .filter((place): place is NominatimPlace => place !== null);
};
