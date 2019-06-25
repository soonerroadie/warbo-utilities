{ bash, fail, jq, jsbeautifier, lynx, raw, wget, wrap, writeScript, xidel }:

with rec {
  f5 = wrap {
    name  = "getvid-f5";
    paths = [ bash jsbeautifier xidel ];
    script = ''
      #!/usr/bin/env bash
      set -e
      wget -q -O- "$1"                                                  |
        xidel -q - -e '//script[contains(text(),"p,a,c,k,e,d")]/text()' |
        js-beautify -                                                   |
        grep -v '\.srt"'                                                |
        grep -o 'file: *"[^"]*'                                         |
        grep -o '".*'                                                   |
        tr -d '"'                                                       |
        head -n1
    '';
  };

  sv = wrap {
    name   = "getvid-sv";
    paths  = [ bash wget ];
    script = ''
      #!/usr/bin/env bash
      if wget -q -O - "$1" > /dev/null
      then
        echo "$1"
        exit 0
      fi
      exit 1
    '';
  };

  voza = wrap {
    name   = "getvid-voza";
    paths  = [ bash wget xidel ];
    script = ''
      #!/usr/bin/env bash
      URL=$(wget -q -O - "$1" | xidel -q -e '//video/source/@src' -)
      echo "$URL" | grep 'http' && exit 0
      exit 1
    '';
  };

  vse = wrap {
    name  = "getvid-vse";
    paths = [ bash lynx ];
    vars  = {
      COLUMNS = "1000";
      cmd     = writeScript "vse-keys" ''
        # Command logfile created by Lynx 2.8.9dev.16 (11 Jul 2017)

        # Submit form
        key Down Arrow
        key Down Arrow
        key Down Arrow
        key Down Arrow
        key Down Arrow
        key Down Arrow
        key Down Arrow
        key ^J

        # View source
        key \
        key y

        # Print to screen
        key p
        key Down Arrow
        key Down Arrow
        key ^J

        # Confirm
        key y
        key ^J

        # Exit
        key ^J
        key q
        key y
      '';
    };
    script = ''
      #!/usr/bin/env bash
      URL=$(lynx -term=linux -accept_all_cookies -cmd_script="$cmd" "$1" |
            grep 'video/mp4' | grep -o 'http[^"]*')
      echo "$URL" | grep 'http' && exit 0
      exit 1
    '';
  };
};
wrap {
  name  = "getvid";
  paths = [ bash xidel ];
  vars  = {
    inherit f5 sv voza vse;
    list = raw."listepurls.sh";
    msg  = ''
      Usage: getvid <listing url>

      Looks through a listing of providers, printing 'TITLE\tURL' to stderr for
      each. Loops through each to see if (a) it has a handler and (b) whether
      the handler returns a working URL. If so, a command for fetching from that
      provider is written to stdout. Set DEBUG=1 to see each handler running.

      Known handlers (e.g. for running standalone) are:
        ${f5}
        ${sv}
        ${voza}
        ${vse}
    '';
  };
  script = ''
    #!/usr/bin/env bash
    set -e

    if [[ "x$1" = "x--help" ]]
    then
      # shellcheck disable=SC2154
      echo "$msg" 1>&2
      exit 0
    fi

    echo "Run with --help as the only arg to see usage and handler scripts" 1>&2

    function esc {
      # shellcheck disable=SC1003
      sed -e "s/'/'"'\\'"'''/g"
    }

    # shellcheck disable=SC2154
    LINKS=$("$list" "$@")

    echo "LINKS: $LINKS" 1>&2

    function tryScrape {
      if echo "$1" | grep "$2" > /dev/null
      then
        # shellcheck disable=SC2154
        [[ -n "$DEBUG" ]] && echo "Running $3 on $1" 1>&2

        # shellcheck disable=SC2154
        URL=$("$3" "$1") || return 0

        [[ -n "$URL" ]] || return 0
        URL=$(echo "$URL" | esc)

        if [[ "x$4" = "xwget" ]]
        then
          echo "wget -c -O '$5' '$URL'"
        fi
        if [[ "x$4" = "xyoutube" ]]
        then
          echo "youtube-dl --output '$5' '$URL'"
        fi
        return 0
      else
        return 1
      fi
    }

    echo "$LINKS" | while read -r PAIR
    do
      LINK=$(echo "$PAIR" | cut -f2)
      [[ -n "$LINK" ]] || continue

      TITLE=$(echo "$PAIR" | cut -f1 | esc)
      [[ -n "$TITLE" ]] || TITLE="UNKNOWN"

      URL=""

      [[ -n "$DEBUG" ]] && echo "Checking $LINK" 1>&2

      # shellcheck disable=SC2154
      tryScrape "$LINK" 'x5[4-6][4-6]\.c' "$f5"   'wget'    "$TITLE" && continue

      # shellcheck disable=SC2154
      tryScrape "$LINK" '/spe....d\.co'   "$sv"   'youtube' "$TITLE" && continue

      # shellcheck disable=SC2154
      tryScrape "$LINK" '/vi..z.\.net/'   "$voza" 'wget'    "$TITLE" && continue

      # shellcheck disable=SC2154
      tryScrape "$LINK" '/vs...e\.e'      "$vse"  'wget'    "$TITLE" && continue
    done
  '';
}
