#!/bin/bash
chmod 777 /opt/sagetv/comskip/*


# Copy scipt in case ffmpeg is upgrade when docker starts
cp -f /opt/sagetv/server/ffmpeg.sh /opt/sagetv/server/ffmpeg 
chmod 777 /opt/sagetv/server/ffmpeg

# Start Docker daemon in background
sudo dockerd --host=unix:///var/run/docker.sock --storage-driver=overlay2 &

# Wait until the daemon is ready
until sudo docker info >/dev/null 2>&1; do
  sleep 1
done
