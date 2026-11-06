# mapterhorn-to-valhalla

Populates a [Valhalla](https://github.com/valhalla/valhalla) elevation directory from the [Mapterhorn](https://mapterhorn.com) terrain tiles, as an alternative to the Tilezen (skadi) tiles that `valhalla_build_elevation` downloads.

Each 1x1 degree cell becomes a 3601x3601 `.hgt` file in Valhalla's layout, for example `N32/N32E034.hgt`. Valhalla's elevation reader loads the files unchanged, raw, `.gz` or `.lz4`.

## How it works

For every selected cell without a file, in any of the `.hgt`, `.hgt.gz` and `.hgt.lz4` formats:

1. `pmtiles extract` copies the zoom-12 tiles of the cell, plus a 0.01 degree margin, from the Mapterhorn archive.
2. GDAL reads them from a local `pmtiles serve`, decodes Terrarium (`R*256 + G + B/256 - 32768`) and warps them with bilinear resampling onto the 1 arc-second grid.
3. The file is written to a temporary name and renamed into place.

- Pixels without Mapterhorn data are written as `-32768`, Valhalla's no-data value.
- A cell without any Mapterhorn data, such as one beyond 85.0511 degrees latitude, gets no file.
- Every processed cell is appended to `.mapterhorn-to-valhalla.progress` in the output directory.

### Migrating

`--migrate` replaces an existing elevation directory, for example one populated by `valhalla_build_elevation`:

- Every selected cell not listed in the progress file is processed, and its files in the other formats are removed.
- The files of a cell without Mapterhorn data are removed.
- With `--from-tiles`, the files of cells outside the graph are removed.

A stopped or killed `--migrate` run resumes where it left off. Delete the progress file to migrate every cell again, for example after a Mapterhorn release.

`SIGTERM` or `SIGINT` lets the cells in progress finish, and no new ones start.

## Usage

```
mapterhorn-to-valhalla [options] [-v...] [-t | -b BBOX | -g DIR] [-d | -z]
```

The cell selection and the output options are those of `valhalla_build_elevation`:

| Option | Meaning |
|---|---|
| `-t`, `--from-tiles` | Cells covered by the level-2 tiles of the graph in `mjolnir.tile_dir` of the config, or else in the `index.bin` of the `mjolnir.tile_extract` tar. The default. |
| `-b`, `--from-bbox BBOX` | Cells intersecting `minX,minY,maxX,maxY`. |
| `-g`, `--from-geojson DIR` | Cells intersecting the polygons of the `.geojson` files in `DIR`. |
| `-c`, `--config FILE` | Valhalla config JSON. |
| `-i`, `--inline-config JSON` | Inline JSON config, overrides `--config`. |
| `-o`, `--outdir DIR` | Output directory, overrides `additional_data.elevation` of the config. |
| `-s`, `--source PMTILES` | Mapterhorn archive URL or path, default `https://download.mapterhorn.com/planet.pmtiles`. |
| `-p`, `--parallelism N` | Cells converted at once, default the number of available cores. |
| `-d`, `--decompress` | Write raw `.hgt` files. |
| `-z`, `--lz4` | Write `.hgt.lz4` files. |
| `-m`, `--migrate` | Replace the existing files of cells not listed in the progress file. |
| `-v` | `-v`: INFO, `-vv`: DEBUG. |

Without `-d` or `-z` the files are gzipped, as with `valhalla_build_elevation`.

## Running

```bash
docker run --rm -v "$PWD/valhalla-build:/custom_files" ghcr.io/mapeak-com/mapterhorn-to-valhalla -c /custom_files/valhalla.json -d -v
```

With Docker Compose, migrating the elevation directory of a `valhalla-scripted` build that mounts the same directory, taking the cells from the graph tar served from `./valhalla`:

```yaml
services:
  mapterhorn-to-valhalla:
    image: ghcr.io/mapeak-com/mapterhorn-to-valhalla:latest
    stop_grace_period: 1m
    volumes:
      - ./valhalla-build:/custom_files
      - ./valhalla:/valhalla:ro
    command:
      - --config=/custom_files/valhalla.json
      - '--inline-config={"mjolnir":{"tile_extract":"/valhalla/valhalla_tiles.tar"}}'
      - --decompress
      - --migrate
      - --verbosity
```

The paths in `valhalla.json` (`additional_data.elevation`) resolve inside the container, so it mounts the directory at the same place as `valhalla-scripted`.

## Development

The executable needs Python 3, the GDAL Python bindings, numpy, docopt and the `pmtiles` CLI on `PATH`; lz4 for `-z` and shapely for `-g`.

The GitHub workflow builds the image, converts `N32E034` from the live archive as a smoke test, and publishes the image to `ghcr.io` on pushes to `main` and `v*` tags.

## Attribution

Elevation data © Mapterhorn, see [mapterhorn.com/attribution](https://mapterhorn.com/attribution).
