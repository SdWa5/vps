# Background removal and shop variants for merch photos, see shop-images.sh.
FROM python:3.12-slim
RUN pip install --no-cache-dir "rembg[cpu]==2.0.84"
# The BiRefNet model (ca. 930 MB) is downloaded on first use into this
# directory, which shop-images.sh mounts from the host cache.
ENV U2NET_HOME=/models
