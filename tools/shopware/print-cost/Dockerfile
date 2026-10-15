# OrcaSlicer CLI for print cost estimates, see print-cost.sh.
#
# The AppImage runtime cannot start in a container, so its squashfs payload is
# unpacked directly. It begins where the ELF runtime ends, at the section header
# table offset plus its size.
FROM ubuntu:24.04
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libwebkit2gtk-4.1-0 libgtk-3-0t64 libgl1 libegl1 libglu1-mesa libgstreamer-plugins-base1.0-0 \
        libosmesa6 libmspack0t64 xvfb xauth locales ca-certificates curl python3 squashfs-tools \
    && rm -rf /var/lib/apt/lists/*

ARG ORCA_VERSION=2.4.2
ARG ORCA_SHA256=d12fb8c8eac1aecd2dfb6377acd48f994f8fa439ed5292fa532dd82880f029fd
RUN curl -fsSL -o /tmp/orca.AppImage \
        "https://github.com/SoftFever/OrcaSlicer/releases/download/v${ORCA_VERSION}/OrcaSlicer_Linux_AppImage_Ubuntu2404_V${ORCA_VERSION}.AppImage" \
    && echo "${ORCA_SHA256}  /tmp/orca.AppImage" | sha256sum -c - \
    && offset="$(python3 -c 'import struct,sys; h=open(sys.argv[1],"rb").read(64); o,s,n=struct.unpack_from("<Q",h,40)[0],*struct.unpack_from("<HH",h,58); print(o+s*n)' /tmp/orca.AppImage)" \
    && unsquashfs -q -n -o "$offset" -d /opt/orca /tmp/orca.AppImage && rm /tmp/orca.AppImage

# The printer the estimates are for. The presets are flattened from Orca's own
# vendor profiles at build time, so none of them is copied into this repository.
ARG PRINTER="Anycubic Kobra 3 Max 0.4 nozzle"
ARG PROCESS="0.20mm Standard @Anycubic Kobra 3 Max 0.4 nozzle"
ARG FILAMENT="Anycubic PLA @Anycubic Kobra 3 Max 0.4 nozzle"
COPY flatten.py slice-inner.sh /usr/local/lib/print-cost/
RUN mkdir /profiles && cd /usr/local/lib/print-cost \
    && python3 -I flatten.py /opt/orca/resources/profiles machine "$PRINTER" /profiles/machine.json \
    && python3 -I flatten.py /opt/orca/resources/profiles process "$PROCESS" /profiles/process.json --printer "$PRINTER" \
    && python3 -I flatten.py /opt/orca/resources/profiles filament "$FILAMENT" /profiles/filament.json --printer "$PRINTER"
ENTRYPOINT ["sh", "/usr/local/lib/print-cost/slice-inner.sh"]
