I created a man-in-the-middle script that enables FFmpeg hardware decoding and encoding using Intel QSV inside the SageTV Linux Docker container. It runs a “Docker inside Docker” setup that uses the linuxserver/ffmpeg image, because the base SageTV Docker is built on an older Ubuntu version that does not support the required Intel drivers. By passing the video device (/dev/dri) from the host into the SageTV container, the script can launch linuxserver/ffmpeg with proper access to the Intel GPU.

The script intercepts the FFmpeg command that SageTV sends and checks whether the request is for MPEG4 transcoding. If it is, the script redirects that job to the linuxserver/ffmpeg container and uses Intel QSV for hardware accelerated H.264 encoding, while still outputting a stream that SageTV can consume. For non-transcode or non-MPEG4 requests, the script falls back to the FFmpeg binary provided by the SageTVTranscoder-FFmpeg plugin, so SageTV still receives the exact output format it expects for parsing. The current implementation is tuned for Intel QSV, but it can be adapted to other hardware or custom FFmpeg parameters and gives full control over how FFmpeg is launched.


# How to install

1. Pass device `/dev/dri` into the SageTV Docker container:

```bash
--device=/dev/dri:/dev/dri
```

2. Install Docker inside the SageTV Docker container:

```bash
# Update package index and install prerequisites
sudo apt-get update
sudo apt-get install ca-certificates curl gnupg

# Add Docker's official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add the Docker repository to Apt sources
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index and install Docker Engine
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin
```

3. Install the SageTVTranscoder-FFmpeg plugin from:

```text
https://github.com/jvl711/SageTVTranscoder-FFmpeg
```

4. In the `/opt/sagetv/server` directory, rename `ffmpeg` to `ffmpeg.run`:

```bash
cd /opt/sagetv/server
mv ffmpeg ffmpeg.run
```

5. In the `/opt/sagetv/server` directory, edit `sagetv-user-script.sh` and add the following lines:

```bash
# Copy script in case ffmpeg is upgraded when Docker starts
cp -f /opt/sagetv/server/ffmpeg.sh /opt/sagetv/server/ffmpeg

# Start Docker daemon in background
sudo dockerd --host=unix:///var/run/docker.sock --storage-driver=overlay2 &

# Wait until the daemon is ready
until sudo docker info >/dev/null 2>&1; do
  sleep 1
done
```

6. Copy `ffmpeg.sh` into the `/opt/sagetv/server` directory:

```bash
cp ffmpeg.sh /opt/sagetv/server/
```

7. Restart the SageTV Docker container.

8. Test the ffmpeg Docker image inside the SageTV Docker container:

```bash
sudo docker run --rm linuxserver/ffmpeg
```
