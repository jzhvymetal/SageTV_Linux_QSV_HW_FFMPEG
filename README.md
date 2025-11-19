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
