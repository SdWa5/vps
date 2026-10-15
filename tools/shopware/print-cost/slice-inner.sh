#!/bin/sh
# Slice each STL under /models with the flattened profiles and print one line
# per model: NAME GRAMS SECONDS. Runs inside the print-cost image.
set -eu
for stl in "$@"; do
    name="$(basename "$stl" .stl)"
    out="$(mktemp -d)"
    if ! xvfb-run -a /opt/orca/bin/orca-slicer --slice 0 --arrange 1 --orient 0 \
        --load-settings "/profiles/machine.json;/profiles/process.json" \
        --load-filaments /profiles/filament.json --outputdir "$out" "/models/$stl" > "$out/log" 2>&1; then
        echo "slicing $stl failed:" >&2; tail -5 "$out/log" >&2; exit 1
    fi
    grams="$(sed -n 's/^; total filament used \[g\] = //p' "$out"/*.gcode | head -1)"
    time="$(sed -n 's/^; estimated printing time (normal mode) = //p' "$out"/*.gcode | head -1)"
    seconds="$(echo "$time" | awk '{s=0; for(i=1;i<=NF;i++){v=$i+0; u=substr($i,length($i)); s+= (u=="d")?v*86400:(u=="h")?v*3600:(u=="m")?v*60:v} print s}')"
    echo "$name $grams $seconds"
    rm -rf "$out"
done
