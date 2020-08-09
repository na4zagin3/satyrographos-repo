#!/bin/bash

set -ex

if [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
    echo "Pull request"
else
    echo "Non pull request"
fi

export PACKAGE="$SNAPSHOT"
bash -ex .travis-opam.sh

FAILED_PACKAGES=failed.pkgs

: > "$FAILED_PACKAGES"

if [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
    echo "Pull request"

    eval $(opam config env)

    sed -i.bak -e '/^# Package List$/,/^# Package List End$/d' "$SNAPSHOT".opam
    opam update

    export OPAMYES=1
    git diff --name-status master | sed -e '/^D/d' -e 's/^\w*\s//' -e '/^packages\//!d' -e 's!\([^/]*/\)\{2\}!!' -e 's!/.*!!' | sort | uniq \
        | while read PACKAGE ; do
        if ! opam install "$SNAPSHOT" "$PACKAGE" --with-test
        then
            echo "$PACKAGE: install" >> "$FAILED_PACKAGES"
            continue
        elif ! opam uninstall "$PACKAGE"
        then
            echo "$PACKAGE: uninstall" >> "$FAILED_PACKAGES"
        fi
    done
else
    echo "Non pull request"
fi

if [ -s "$FAILED_PACKAGES" ] ; then
    sed -e 's/^/- /' -e "iFailed packages:" "$FAILED_PACKAGES" 1>&2
    exit 1
fi
