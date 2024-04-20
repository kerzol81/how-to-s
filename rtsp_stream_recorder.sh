#!/bin/bash
set -x

CONFIG="$(basename $0).cfg"

source "$CONFIG" || exit 1

BASENAME=$(basename "$0")
LOGPATH="$WORKDIR"log/ && mkdir -p "$LOGPATH"
PIDPATH="$WORKDIR"pid/ && mkdir -p "$PIDPATH"

DST=$pwd

OPTSTRING=":i:d:e:s:t:"

while getopts ${OPTSTRING} opt; do
  case ${opt} in
    i)
      RTSP_URL=${OPTARG}
      ;;
    d)
      FOLDER=${OPTARG}
      ;;
    e)
      EXT=${OPTARG}
      ;;
    s)
      SPLIT=${OPTARG}
      ;;
    t)
      RTSP_TRANSPORT=${OPTARG}
      ;;
    ?)
      echo "$(date "+%F %H:%M:%S") Invalid option: -${OPTARG} EXIT (1)"
      exit 1
      ;;
  esac
done

PID="$PIDPATH$(basename "$0")_$IP_$FOLDER.pid" 
LOG="$LOGPATH$(basename "$0")_$IP_$FOLDER.log"

pgrep -F "$PID"
pid_is_stale=$?
if [ $pid_is_stale -eq 1 ]; then
    rm -rf $PID
fi
#
if [ -f "$PID" ]
    then
        echo "$(date "+%F %H:%M:%S") OTHER INSTANCE IS RUNNING, EXIT (0)" >> "$LOG" 2>&1
        exit 0
else
    touch "$PID"
    echo $$ > $PID
fi


if ffprobe "$RTSP_URL" 2>&1 | grep 'Stream';then
    echo "$(date "+%F %H:%M:%S") RTSP STREAM RECORDING STARTED, URL:$RTSP_URL EXTENSION: $EXT RTSP TRANSPORT: $RTSP_TRANSPORT FOLDER: $FOLDER" >> "$LOG" 2>&1
else
    echo "$(date "+%F %H:%M:%S") MISSING STREAM, URL:$RTSP_URL , EXIT (0)" >> "$LOG" 2>&1
    rm "$PID"
    exit 1
fi

while true;
do

        TODAY=$(date "+%Y-%m-%d")
        mkdir -p "$TODAY"
        RECORDING=$(date "+%Y-%m-%d__%H_%M_%S")
        ffmpeg -i $RTSP_URL -y -stimeout 50000 -t $SPLIT -rtsp_transport $RTSP_TRANSPORT $TODAY/$RECORDING.$EXT | tee -a "$LOG" 2>&1 || exit 1 
    
done
rm -rf $PID

echo "$(date "+%F %H:%M:%S") DONE, EXIT (0)" >> "$LOG" 2>&1
