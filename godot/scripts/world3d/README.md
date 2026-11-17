# Shared 3D display adapter

`world3d_view.gd` embeds a `SubViewport` in an ordinary `Control`. It never sends
commands, advances combat, writes a profile, chooses a route, or generates a
physical height source. Existing home/land/naval controls retain those roles.

## Input and coordinates

- `observe(land, playing)` consumes native observations. For
  `cas-coastal-geography-v1`, the first observation must contain the full validated
  snapshot in `land.geography`. Later light headers reuse it only when their
  `geometry_hash` matches. Other hashes never borrow a grid.
- `set_camera(core_center, zoom)`, `set_miniature(bool)`, `focus_at(core_xy)`;
  `set_chart_camera(core_center, metres_per_pixel)` supplies an exact top view.
- `project`, `unproject`, `pick_at`, `is_point_visible`, `visibility_at` operate
  on the original native metre coordinates. Core `(x,y)` becomes Godot
  `(x-origin.x, height, y-origin.y)`. The top camera texture and both projections
  mirror X together, retaining east-right and north-up.
- A command ray hits the nearest visible surface. A unit hidden behind a hill
  consequently does not have an invertible screen position; use
  `is_point_visible` when auditing round trips.
- `height_at` is the imported ground height. `surface_at`/actor placement also
  respect a higher native inland water level or the ocean's zero level. Outside
  the imported grid, a -32 m visual seabed supplies the ocean horizon; this is
  not a new native depth, collision, or landing claim.

`geography_grid.gd` reproduces the frozen native row-major heights using
`a,b,c / b,d,c` triangles and the same `u+v<=1` interpolation. The mesh uses those
vertices and indices directly. Road decals are clipped against those same
triangles in island-local coordinates, avoiding floating-point cancellation at
large native coordinates. The previous zone/ramp path remains separately
supported; it is never silently smoothed into a different physical surface.

## Rendering and budget

Only female body sprites use `Sprite3D`, with the registered per-frame foot
anchor and mirror handling. Each vehicle has a stable native ID and a real 3D
model. Models use original metre dimensions and a common -Z forward direction.
The display-only SD person height is 5 m for readability; it does not change
collision, range, movement, or any simulation coordinate.

The approved coastal Demo supplies the original building mesh modules, CC0
vegetation and vehicle models, palette, grain texture parameters, sea lighting,
animated wave normals/foam, inland water and grass. Geometry is rebuilt only
when the static geography/building key changes. Near vegetation/ground props
use deterministic 256 m chunks and `MultiMesh` batches; roads and their markings
are batched. A moving bounded sea grid/depth texture keeps near-water detail
independent of the whole naval map's size. Phone mode reduces water resolution,
foliage density, AA and shadows. No real Android performance claim is made.

Sources, file hashes and licences are recorded in
`godot/assets/world3d/reuse-manifest.json` and the adjacent licence files.

## Checks

- `check_world3d.gd`: verified old native fixture, camera axes/scale, 225-pixel
  round trips, continuous contract, stable IDs, real vehicle mesh, fixed anchors.
- `check_facilities.gd`: 13 current facility kinds have non-empty real 3D models;
  `-- --capture` takes actual GPU close-ups for visual inspection.
- `check_coastal_grid.gd`: **pending-core art fixture only**, reads the frozen
  Demo input without a playable native session, checks native-style grid sampling
  and clipped road area, takes actual GPU whole/coast/90 m/30 km screenshots.
  It does not substitute for the root real-Main/core review.
