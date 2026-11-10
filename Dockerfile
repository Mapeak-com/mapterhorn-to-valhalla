FROM ghcr.io/osgeo/gdal:ubuntu-small-3.13.3 AS pmtiles
ADD --checksum=sha256:3ed7dbf4ec2e6dfe5e25b6f70d1ffc932729f93c86db353bf514dd71010a312f https://github.com/protomaps/go-pmtiles/releases/download/v1.31.2/go-pmtiles_1.31.2_Linux_x86_64.tar.gz /tmp/pmtiles.tar.gz
RUN tar -xzf /tmp/pmtiles.tar.gz -C /usr/local/bin pmtiles

FROM ghcr.io/osgeo/gdal:ubuntu-small-3.13.3
RUN apt-get update \
  && apt-get install -y --no-install-recommends python3-docopt python3-lz4 python3-shapely python3-tqdm \
  && rm -rf /var/lib/apt/lists/*
COPY --from=pmtiles /usr/local/bin/pmtiles /usr/local/bin/pmtiles
COPY mapterhorn-to-valhalla /usr/local/bin/mapterhorn-to-valhalla
ENTRYPOINT ["mapterhorn-to-valhalla"]
