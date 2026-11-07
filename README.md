# mapterhorn-to-valhalla

Writes [Valhalla](https://github.com/valhalla/valhalla) elevation files from the [Mapterhorn](https://mapterhorn.com) terrain tiles, instead of the Tilezen (skadi) tiles that `valhalla_build_elevation` downloads.

The skadi tiles date from 2016: the files on the `elevation-tiles-prod` bucket were last modified in April 2016. Mapzen's [Terrain Tiles v1.1](https://www.mapzen.com/blog/terrain-tiles-v1.1/) update of December 2017 did not regenerate them, even in the areas it improved, such as Austria, Norway, the UK and New Zealand.

## Overview

Each 1x1 degree cell becomes a 3601x3601 `.hgt` file in Valhalla's layout, for example `N32/N32E034.hgt`. Valhalla's elevation reader loads the files unchanged, raw, `.gz` or `.lz4`.

There are two ways to use it:

1. [Instead of `valhalla_build_elevation`](#instead-of-valhalla_build_elevation), to populate the elevation directory of a graph.
2. [Migrating an existing elevation directory](#migrating-an-existing-elevation-directory) to Mapterhorn.

## Instead of `valhalla_build_elevation`

Run it with the same arguments:

```bash
valhalla_build_elevation --from-tiles --decompress -c valhalla.json -v
mapterhorn-to-valhalla   --from-tiles --decompress -c valhalla.json -v
```

With Docker, for a Valhalla directory `./valhalla` mounted at `/custom_files`, as with `valhalla-scripted`:

```bash
docker run --rm -v ./valhalla:/custom_files ghcr.io/mapeak-com/mapterhorn-to-valhalla --from-tiles --decompress -c /custom_files/valhalla.json -v
```

It takes the flags of `valhalla_build_elevation` with the same meaning, writes the same layout and compression, and, like it, writes only cells without a file and removes nothing. Run it where `valhalla_build_elevation` runs, between `valhalla_build_tiles -e build` and `valhalla_build_tiles -s enhance`, or before a build, on the previous graph.

Differences:

- Without `-t`, `-b` or `-g` it selects the cells as `-t` does.
- `-t` reads the `index.bin` of `mjolnir.tile_extract` when `mjolnir.tile_dir` has no level-2 tiles.
- A cell with a file in any of the `.hgt`, `.hgt.gz` and `.hgt.lz4` formats counts as existing, so no second file is written beside it.
- A cell without any Mapterhorn data, such as one beyond 85.0511 degrees latitude, gets no file.
- `-p` is the number of cells converted at once.
- It exits with 1 when a cell failed.

## Migrating an existing elevation directory

`--migrate` replaces the files of an existing elevation directory, for example one populated by `valhalla_build_elevation`. Every processed cell is appended to `.mapterhorn-to-valhalla.progress`, so a migration can be stopped and resumed:

- `SIGTERM` or `SIGINT` lets the cells in progress finish, and no new ones start. A second one stops at once.
- A killed run leaves complete files only; the next run removes its temporary files.
- Running the same command again continues with the cells not listed yet.
- Deleting the progress file migrates every cell again, for example after a Mapterhorn release.
- Every selected cell not listed in `.mapterhorn-to-valhalla.progress` is written, and its files in the other formats are removed.
- The files of a cell without Mapterhorn data are removed.
- With `--from-tiles`, the files of cells outside the graph are removed.

### With Docker Compose

The paths in `valhalla.json`, such as `additional_data.elevation`, resolve inside the container, so the examples mount the Valhalla directories at the same place as `valhalla-scripted`, `/custom_files`. `docker stop` stops the migration; `stop_grace_period` gives the cells in progress time to finish.

A single Valhalla directory, `./valhalla`, holding the config, the graph tiles and the elevation files:

```yaml
services:
  mapterhorn-to-valhalla:
    image: ghcr.io/mapeak-com/mapterhorn-to-valhalla:latest
    stop_grace_period: 1m
    volumes:
      - ./valhalla:/custom_files
    command:
      - --config=/custom_files/valhalla.json
      - --decompress
      - --migrate
      - --verbosity
```

Separate directories for the build and the server:

- `./valhalla-build`, used by the build, holds the config and the elevation files.
- `./valhalla-server`, used by the server, holds the graph tiles, `valhalla_tiles.tar`.

The migration writes the elevation files in the build directory, for the cells of the graph served from the server directory:

```yaml
services:
  mapterhorn-to-valhalla:
    image: ghcr.io/mapeak-com/mapterhorn-to-valhalla:latest
    stop_grace_period: 1m
    volumes:
      - ./valhalla-build:/custom_files
      - ./valhalla-server:/valhalla:ro
    command:
      - --config=/custom_files/valhalla.json
      - '--inline-config={"mjolnir":{"tile_extract":"/valhalla/valhalla_tiles.tar"}}'
      - --decompress
      - --migrate
      - --verbosity
```

`--inline-config` points `mjolnir.tile_extract` of the build config to the graph tar of the server.

## How it works

For every cell to write:

1. `pmtiles extract` copies the zoom-12 tiles of the cell, plus a 0.01 degree margin, from the Mapterhorn archive.
2. GDAL reads them from a local `pmtiles serve`, decodes Terrarium (`R*256 + G + B/256 - 32768`) with a VRT `expression` pixel function, and warps them with bilinear resampling onto the 1 arc-second grid. The warp streams the cell in chunks, so a conversion needs up to about 1 GB at any latitude.
3. The file is written to a temporary name and renamed into place.

Pixels without Mapterhorn data are written as `-32768`, Valhalla's no-data value.

## Usage

```
mapterhorn-to-valhalla [options] [-v...] [-t | -b BBOX | -g DIR] [-d | -z]
```

| Option | Meaning |
|---|---|
| `-t`, `--from-tiles` | Cells covered by the level-2 tiles of the graph in `mjolnir.tile_dir` of the config, or else in the `index.bin` of the `mjolnir.tile_extract` tar. The default. |
| `-b`, `--from-bbox BBOX` | Cells intersecting `minX,minY,maxX,maxY`. |
| `-g`, `--from-geojson DIR` | Cells intersecting the polygons of the `.geojson` files in `DIR`. |
| `-c`, `--config FILE` | Valhalla config JSON. |
| `-i`, `--inline-config JSON` | Inline JSON config, overrides `--config`. |
| `-o`, `--outdir DIR` | Output directory, overrides `additional_data.elevation` of the config. |
| `-s`, `--source PMTILES` | Mapterhorn archive URL or path, default `https://download.mapterhorn.com/planet.pmtiles`. |
| `-p`, `--parallelism N` | Cells converted at once, default the number of available cores. Each needs up to about 1 GB of memory. |
| `-d`, `--decompress` | Write raw `.hgt` files. |
| `-z`, `--lz4` | Write `.hgt.lz4` files. |
| `-m`, `--migrate` | Replace the existing files of cells not listed in the progress file. |
| `-v` | `-v`: INFO, `-vv`: DEBUG. On a terminal, INFO shows a progress bar with the latest cell, rate and time left, instead of a line per cell. When the run ends or stops, INFO logs the peak and retained memory of the conversions; DEBUG logs them per cell. |

Without `-d` or `-z` the files are gzipped, as with `valhalla_build_elevation`.

## Development

The executable needs Python 3, the GDAL Python bindings, numpy, docopt and the `pmtiles` CLI on `PATH`; lz4 for `-z` and shapely for `-g`.

The GitHub workflow builds the image, converts `N32E034` from the live archive as a smoke test, and publishes the image to `ghcr.io` on pushes to `main` and `v*` tags.

## Attribution

Elevation data © Mapterhorn, see [mapterhorn.com/attribution](https://mapterhorn.com/attribution).

Created with Claude AI
