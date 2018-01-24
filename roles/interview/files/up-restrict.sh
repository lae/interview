#!/bin/bash -fue
function log() {
    if [ -z "$*" ]; then msg="unknown action"; else msg="$*"; fi
    timestamp=$(date +"%Y.%m.%d %H:%M:%S")
    ip=$(echo $SSH_CONNECTION | awk '{print $1}')
    echo "$timestamp $ip $msg" >> /home/lae/up.log
}
function error() {
    if [ -z "$*" ]; then details="request not permitted"; else details="$*"; fi
    log "raised an error: $details"
    >&2 echo -e "ERROR: $details"
    exit 1
}

soc=${SSH_ORIGINAL_COMMAND:-}
if [ "x$soc" == x ]; then error "no shell access"; fi
set -- $soc # passes the SSH command to ARGV

tmp='/tmp/up.lae.is/'
host="https://up.lae.is"
up='/home/lae/up/u/'
img='/home/lae/up/i/'
paste='/home/lae/up/p/'

case "$1" in
"scp")
    if [ "$2" != "-t" ]; then error; fi # checks flags for local scp to retrieve a file
    if [ ! -e $tmp ]; then mkdir $tmp; fi # create tmp directory
    if [ ! -d $tmp ]; then error "failed to use temporary directory"; fi
    shift
    shift
    if [[ "$@" == '.' ]]; then error "destination not specified"; fi # checks that the command isn't scp -t .
    if [[ "$@" == ../* ]] || [[ "$@" == ./* ]] || [[ "$@" == /* ]] || [[ "$@" == */* ]] || [[ "$@" == .. ]]; then
      error "destination traverses directories"
    fi
    if [[ -f "$tmp$@" ]]; then error "file exists on server in tmp"; fi
    log "uploaded $@"
    eval "scp -t '$tmp$@'"
;;
"tmp-uri")
    file="$(basename ${2:-})"
    if [ "x$file" == x ]; then error "file not specified"; fi
    s="$tmp$file"
    if [ ! -e "$s" ]; then error "$file does not exist"; fi
    uri="$host/tmp/$file"
    exec echo "$uri"
;;
"from-web")
    web_uri="${2:-}"
    if [ ! $(echo "$web_uri" | grep -P "^https?:\/\/") ]; then
        error "$web_uri is not an HTTP location"
    fi
    tn=${web_uri##*/}
    tn=${tn%%\?*}
    s="$tmp$tn"
    if [[ -f "$s" ]]; then error "file exists on server in tmp"; fi
    if wget -qO "$s" "$web_uri"; then
        exec echo "$tn"
    else
        rm "$s"
        error "could not fetch $web_uri"
    fi
;;
"push")
    pool=${2:-}
    file="$(basename ${3:-})"
    if [ "x$file" == x ]; then error "file not specified"; fi
    s="$tmp$file"
    if [ ! -e "$s" ]; then error "file does not exist"; fi
    chmod 644 "$s"
    case $pool in
    "image")
        now=$(date +%s)
        sha1=$(sha1sum "$s" | cut -d' ' -f1)
        h=$(echo $sha1 | awk '{printf substr($1, length($1) - 4, length($1))}')
        matches=$(find $img -type f -iname "*$h*")
        if [ "x$matches" != x ]; then
            for match in $matches; do
                m_sha1=$(sha1sum $match | cut -d' ' -f1)
                if [ $sha1 == $m_sha1 ]; then
                    rm "$s"
                    exec echo -e "image already exists at:\n$host/i/$(basename $match)"
                fi
            done
        fi
        ext=${s##*.}
        name=$now-$h.$ext
        uri="$host/i/$name"
        dest=$img$name
    ;;
    "paste")
        now=$(date +%s)
        sha1=$(sha1sum "$s" | cut -d' ' -f1)
        h=$(echo $sha1 | awk '{printf substr($1, length($1) - 4, length($1))}')
        matches=$(find $paste -type f -iname "*$h*")
        if [ "x$matches" != x ]; then
            for match in $matches; do
                m_sha1=$(sha1sum $match | cut -d' ' -f1)
                if [ $sha1 == $m_sha1 ]; then
                    rm "$s"
                    exec echo -e "paste already exists at:\n$host/i/$(basename $match)"
                fi
            done
        fi
        ext=${s##*.}
        name=$now-$h.$ext
        uri="$host/p/$name"
        dest=$paste$name
    ;;
    "file")
        uri="$host/u/$file"
        dest="$up$file"
    ;;
    esac
    mv "$s" "$dest"
    log "moved $s to $dest"
    exec echo "$uri"
;;
esac

# facility 1: upload to tmp
# 2: for images, hash check against possible duplicates, print duplicate name
# 3: push to up dir
