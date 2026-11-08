// Satellite chart underlay for the Iron Bottom Sound scenarios.
//
// The mosaic is built from the cached ArcGIS World_Imagery tiles by
// scripts/build-map-mosaics.py; each scenario registers the real lonlat of
// its engine field origin (x=0 at lon_w, y=0 at lat_origin — the field's
// south edge, because engine y grows northward) so the image lands under the
// ships exactly.
type Bounds = { lon_w: number; lon_e: number; lat_n: number; lat_s: number };
type Basemap = { src: string; bounds: Bounds; field: { lon_w: number; lat_origin: number } };

const MOSAIC: Bounds = { lon_w: 158.203125, lon_e: 161.015625, lat_n: -8.059229627200187, lat_s: -10.141931686131025 };

const MAPS: Record<string, Basemap> = {
  savo: { src: '/maps/ironbottom.jpg', bounds: MOSAIC, field: { lon_w: 159.5834, lat_origin: -9.417 } },
  esperance: { src: '/maps/ironbottom.jpg', bounds: MOSAIC, field: { lon_w: 159.5894, lat_origin: -9.3419 } },
  tassafaronga: { src: '/maps/ironbottom.jpg', bounds: MOSAIC, field: { lon_w: 159.6902, lat_origin: -9.3545 } },
};

export function basemapFor(variant?: string): Basemap | undefined {
  return variant ? MAPS[variant] : undefined;
}

export type { Basemap, Bounds };
