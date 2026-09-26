# Test fixtures

These files are synthetic. They copy the shape of real Overpass JSON, but the
elements are made up. Tests must not call the live Overpass server.

- `overpass-sample.json` — one element for each classification and exclusion rule,
  one way with `center`, one relation with no position, and one node with no tags.
- `overpass-timeout.json` — HTTP 200 response with a runtime-error `remark`.
