{ artemis, git, git2html, makeWrapper, mhonarc, pandoc, stdenv, writeScript }:

with rec {
  # Use as EDITOR to write a given artemis message
  testEditor = writeScript "test-editor" ''
    #!/usr/bin/env bash
    sed -i -e "s@^Subject: .*@Subject: $SUBJECT@g" "$1"
    sed -i -e "s@Detailed description.@$BODY@g"    "$1"
  '';

  src = writeScript "genGitHtml-raw" ''
    #!/usr/bin/env bash
    set -e
    shopt -s nullglob

    [[ "$#" -eq 2 ]] || {
      echo "Usage: genGitHtml <repo-path> <destination>" 1>&2
      echo "Optionally, set REPO_LINK to your base URL"  1>&2
      exit 1
    }

    repoPath="$1"
    if echo "$repoPath" | grep '^/' > /dev/null
    then
      repoPath="file://$repoPath"
    fi

    repoName=$(basename "$repoPath" .git)

    [[ -n "$REPO_LINK" ]] || REPO_LINK="http://chriswarbo.net/git/$repoName.git"

    echo "Generating pages from git history" 1>&2
    mkdir -p "$2/git"

    #        Name           Source repo    Base URL        Destination
    git2html -p "$repoName" -r "$repoPath" -l "$REPO_LINK" "$2/git"

    echo "Generating pages from issue tracker" 1>&2
    mkdir "$2/issues"

    if [[ -e "$2/git/repository/.issues" ]]
    then
      mhonarc -mhpattern '^[^\.]' -outdir "$2/issues" \
              "$2"/git/repository/.issues/*/new \
              "$2"/git/repository/.issues/*/cur
    else
      # No issues, write a placeholder instead
      echo '<html><body>No .issues</body></html>' > "$2/issues/threads.html"
    fi

    echo "Generating index page" 1>&2
    README_MSG="No README found"
    README=""
    for F in README.md README README.txt
    do
      if [[ -e "$2/git/repository/$F" ]]
      then
        README_MSG=$(echo -e "Contents of $f follows\n\n---\n\n")
        README=$(cat "$2/git/repository/$F" | sed -e 's/</&lt;/g' |
                                              sed -e 's/>/&gt;/g' )
      fi
    done

    pushd "$2/git/repository"
      DATE=$(git log -n 1 --format=%ci)
    popd

    function render() {
    TICK='`'

    cat <<EOF
    ---
    title: "$repoName"
    ---

    *Last updated: $DATE*

    ''${TICK}git clone $REPO_LINK''${TICK}

    [View repository](git/index.html)
    [View issue tracker](issues/threads.html)

    $README_MSG
    $README
    EOF
    }

    render | pandoc -f markdown -o "$2/index.html"

    # Kill the cloned repo to save space.
    rm -rf "$2/git/repository"

    # Kill mhonarc's database
    rm -f "$2/issues/.mhonarc.db"
  '';
};
stdenv.mkDerivation {
  inherit src;
  name        = "genGitHtml";
  buildInputs = [ artemis git git2html makeWrapper mhonarc pandoc ];
  unpackPhase = "true";

  doCheck    = true;
  checkPhase = ''
    function fail() {
      echo -e "$*" 1>&2
      find . 1>&2
      exit 1
    }

    mkdir home
    export HOME="$PWD/home"
    git config --global user.email "you@example.com"
    git config --global user.name "Your Name"
    export EDITOR="${testEditor}"

    mkdir html
    mkdir test.git
    pushd test.git
      git init
      SUBJECT="Need a foo" BODY="For testing" git artemis add
      echo "Testing" > foo
      git add foo
      git commit -m "Added foo"

      SUBJECT="Need a bar" BODY="More testing" git artemis add
      echo "Testing" >> foo
      echo "123" > bar
      git add foo bar
      git commit -m "Added bar"
    popd

    if "$src"
    then
      fail "Should reject when no args"
    fi

    if "$src" test.git
    then
      fail "Should reject when one arg"
    fi

    "$src" test.git html

    if [[ -e test.git/repository ]]
    then
      fail "Left over repo should have been deleted"
    fi

    [[ -e html/index.html          ]] || fail "No index.html generated"
    [[ -e html/git/index.html      ]] || fail "No git/index.html generated"
    [[ -e html/issues/threads.html ]] || fail "No issues/threads.html generated"
  '';

  installPhase = ''
    makeWrapper "$src" "$out" \
      --prefix PATH : "${git2html}/bin" \
      --prefix PATH : "${mhonarc}/bin"  \
      --prefix PATH : "${pandoc}/bin"
  '';
}