{ coreutils, fail, firefox, utillinux, wrap, writeScript, xdotool, xsel,
  xvfb_run }:
with rec {
  # Hack to avoid unwanted quasiquotes
  braced = s: "$" + "{" + s + "}";

  xvfbrunsafe = wrap {
    name   = "xvfb-run-safe";
    paths  = [ fail utillinux xvfb_run ];
    script = ''
      #!/usr/bin/env bash
      set -e

      # allow settings to be updated via environment
      : "${braced "xvfb_lockdir:=/tmp/xvfb-locks"}"
      : "${braced "xvfb_display_min:=99"}"
      : "${braced "xvfb_display_max:=599"}"

      PERMISSIONS=$(stat -L -c "%a" "$xvfb_lockdir")
            OCTAL="0$PERMISSIONS"
         WRITABLE=$(( OCTAL & 0002 ))

      if [[ "$WRITABLE" -ne 2 ]]
      then
        echo "ERROR: xvfb_lockdir '$xvfb_lockdir' isn't world writable" 1>&2
        fail "This may cause users to clobber each others' DISPLAY"     1>&2
      fi

      mkdir -p -- "$xvfb_lockdir" ||
        fail "Couldn't make xvfb_lockdir '$xvfb_lockdir'"

      i="$xvfb_display_min"     # minimum display number
      while (( i < xvfb_display_max ))
      do
        if [ -f "/tmp/.X$i-lock" ]
        then
          # still avoid an obvious open display
          (( ++i ))
          continue
        fi

        # open a lockfile
        exec 5> "$xvfb_lockdir/$i" || {
          # Skip if e.g. permission denied
          (( ++i ))
          continue
        }

        # try to lock it
        if flock -x -n 5
        then
          # if locked, run xvfb-run
          exec xvfb-run --server-num="$i" "$@"
        fi
        (( i++ ))
      done
    '';
  };

  ff = wrap {
    name   = "firefox-runner";
    paths  = [ coreutils firefox xdotool xsel ];
    script = ''
      #!/usr/bin/env bash

      FF_DIR=$(mktemp -d -t 'ff.sh-XXXXX')

      echo "Opening Firefox on '$URL'" 1>&2
      [[ -n "$TIMEOUT" ]] || TIMEOUT=60
      timeout "$TIMEOUT" firefox -safe-mode         \
                                 -profile "$FF_DIR" \
                                 -no-remote         \
                                 -new-instance      \
                                 "$URL" 1>&2 &
      FF_PID="$!"
      sleep 10

      echo "Skipping safe mode prompt" 1>&2
      xdotool key --clearmodifiers Return
      sleep 15

      [[ -z "$FF_EXTRA_CODE" ]] || "$FF_EXTRA_CODE"

      echo "Opening Web console" 1>&2
      xdotool key ctrl+shift+K
      sleep 10

      echo "Extracting body HTML" 1>&2

      # shellcheck disable=SC2016
      xdotool type 'window.prompt("Copy to clipboard: Ctrl+C, Enter", document.body.innerHTML);'

      sleep 5
      xdotool key --clearmodifiers Return
      sleep 5

      echo "Copying content" 1>&2
      xdotool key ctrl+c
      sleep 5

      echo "Pasting content" 1>&2
      xsel --clipboard
      echo ""

      kill "$FF_PID"
      rm -rf "$FF_DIR"
    '';
  };
};
writeScript "ff" ''
  #!/usr/bin/env bash
  URL="$1" "${xvfbrunsafe}" "${ff}"
''
