#!/bin/bash

########################################################################
# User options
########################################################################

# QSV preset for h264_qsv
# Common values: veryfast, faster, fast, medium, slow
QSV_PRESET="veryfast"

# Should audio be reencoded to AC3, or copied from source
# "yes"  -> reencode to AC3 (stereo, 128k, 48k)
# "no"   -> c:a copy
AUDIO_REENCODE="no"

########################################################################
# Script starts here
########################################################################

LOGFILE="/opt/sagetv/server/ffmpeg-commands.log"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

# Log date/time and full original command
{
  printf '%s ' "$(timestamp)"
  printf '/opt/sagetv/server/ffmpeg.run -fflags +genpts'
  printf ' %s' "$@"
  printf '\n'
} >> "$LOGFILE"

args=("$@")
convert=false

# Detect if MPEG4 video codec is used
for ((i=0; i<${#args[@]}-1; i++)); do
  if [[ ${args[i]} == "-vcodec" && ${args[i+1]} == "mpeg4" ]]; then
    convert=true
    break
  fi
done

if "$convert"; then
  ###################################################################
  # QSV / docker path for -vcodec mpeg4
  ###################################################################

  # Defaults from your example
  input_file=""
  start_time=""
  format=""
  bitrate="4M"              # -b:v
  framerate="30000/1001"
  size="1920x1080"
  gop="300"
  bf="0"
  abitrate="128k"
  arate="48000"
  achannels="2"
  map_args=()

  # Track if Sage explicitly set -s
  size_set=false

  # Extract parameters from original args
  for ((i=0; i<${#args[@]}; i++)); do
    case "${args[i]}" in
      -i)
        if (( i + 1 < ${#args[@]} )); then
          input_file="${args[i+1]}"
        fi
        ;;
      -ss)
        if (( i + 1 < ${#args[@]} )); then
          start_time="${args[i+1]}"
        fi
        ;;
      -b)
        if (( i + 1 < ${#args[@]} )); then
          bitrate="${args[i+1]}"
        fi
        ;;
      -r)
        if (( i + 1 < ${#args[@]} )); then
          framerate="${args[i+1]}"
        fi
        ;;
      -s)
        if (( i + 1 < ${#args[@]} )); then
          size="${args[i+1]}"
          size_set=true
        fi
        ;;
      -g)
        if (( i + 1 < ${#args[@]} )); then
          gop="${args[i+1]}"
        fi
        ;;
      -bf)
        if (( i + 1 < ${#args[@]} )); then
          bf="${args[i+1]}"
        fi
        ;;
      -ab)
        if (( i + 1 < ${#args[@]} )); then
          abitrate="${args[i+1]}"
        fi
        ;;
      -ar)
        if (( i + 1 < ${#args[@]} )); then
          arate="${args[i+1]}"
        fi
        ;;
      -ac)
        if (( i + 1 < ${#args[@]} )); then
          achannels="${args[i+1]}"
        fi
        ;;
      -f)
        if (( i + 1 < ${#args[@]} )); then
          format="${args[i+1]}"
        fi
        ;;
      -map)
        if (( i + 1 < ${#args[@]} )); then
          map_args+=("-map" "${args[i+1]}")
        fi
        ;;
    esac
  done

  # Safety defaults if something was missing
  [[ -z "$input_file" ]] && input_file="/var/media/unknown.ts"
  if (( ${#map_args[@]} == 0 )); then
    map_args+=("-map" "0:0" "-map" "0:1")
  fi

  # Split WxH for scale_qsv
  w="${size%x*}"
  h="${size#*x}"

  # Unique container name per script process
  container_name="ffmpeg_qsv_$$"

  # Build docker command
  docker_cmd=(sudo docker run --rm
    --name "$container_name"
    --device=/dev/dri:/dev/dri/
    -v /var/media:/var/media
    linuxserver/ffmpeg
    -init_hw_device qsv=hw:/dev/dri/renderD128
    -hwaccel qsv -hwaccel_device hw -hwaccel_output_format qsv
    -y
    -fflags +genpts
    -sn
  )

  # Keep seek if present
  if [[ -n "$start_time" ]]; then
    docker_cmd+=(-ss "$start_time")
  fi

  # Input file
  docker_cmd+=(
    -i "$input_file"
  )

  # Only scale if Sage actually requested -s
  if $size_set; then
    docker_cmd+=(-vf "scale_qsv=w=${w}:h=${h}")
  fi

  # Video encoder: QSV with user selectable preset
  docker_cmd+=(
    -c:v h264_qsv
    -preset "$QSV_PRESET"
    -low_power 1
    -b:v "$bitrate"
    -r "$framerate"
    -g "$gop"
    -bf "$bf"
  )

  # Audio: reencode or copy based on AUDIO_REENCODE
  if [[ "$AUDIO_REENCODE" == "yes" ]]; then
    docker_cmd+=(
      -c:a ac3 -b:a "$abitrate" -ar "$arate" -ac "$achannels"
    )
  else
    docker_cmd+=(
      -c:a copy
    )
  fi

  # Map streams
  docker_cmd+=("${map_args[@]}")

  # Force mpegts
  docker_cmd+=(-f "mpegts")

  # Output to stdout (Sage still reads from pipe)
  docker_cmd+=("-")

  # Log converted docker command
  {
    printf '%s ' "$(timestamp)"
    printf 'DOCKER CMD: '
    printf '%s ' "${docker_cmd[@]}"
    printf '\n'
  } >> "$LOGFILE"

  ###################################################################
  # Emulate basic stdinctrl behavior and clean up on pipe break
  ###################################################################

  ffmpeg_pid=""
  stdin_watcher_pid=""

  # Forward SIGINT/SIGTERM to child ffmpeg
  forward_sig() {
    if [[ -n "$ffmpeg_pid" ]]; then
      kill -TERM "$ffmpeg_pid" 2>/dev/null || true
    fi
  }
  trap forward_sig INT TERM

  # Start docker/ffmpeg in background
  (
    "${docker_cmd[@]}" 2> >(
      while IFS= read -r line; do
        printf '%s [DOCKER/FFMPEG] %s\n' "$(timestamp)" "$line" >>"$LOGFILE"
        printf '%s\n' "$line" >&2
      done
    ) < /dev/null
  ) &
  ffmpeg_pid=$!

  # Watch stdin for stop commands and kill ffmpeg when seen
  stdin_watcher() {
    while IFS= read -r line; do
      printf '%s [STDINCTRL] %s\n' "$(timestamp)" "$line" >>"$LOGFILE"

      case "$line" in
        STOP*|Stop*|stop*|QUIT*|Quit*|quit*|Q|q)
          kill -TERM "$ffmpeg_pid" 2>/dev/null || true
          ;;
      esac
    done
  }

  stdin_watcher &
  stdin_watcher_pid=$!

  # Wait for docker run (the client) to exit
  wait "$ffmpeg_pid"
  status=$?

  # Kill stdin watcher if still running
  kill "$stdin_watcher_pid" 2>/dev/null || true

  # Ensure the container is gone even if the pipe broke and docker exited early
  sudo docker rm -f "$container_name" >/dev/null 2>&1 || true

  exit "$status"

else
  ###################################################################
  # No mpeg4 vcodec found; run original SageTV ffmpeg with stdinctrl
  ###################################################################
  exec /opt/sagetv/server/ffmpeg.run -fflags +genpts "${args[@]}"
fi
