#!/bin/bash

set -ex

if [ "$TRAVIS_PULL_REQUEST" != "false" ]; then
    echo "Pull request"
else
    echo "Non pull request"
fi

# Set up OPAM and install the snapshot
export PACKAGE="$SNAPSHOT"
bash -ex .travis-opam.sh

# Check validity of the OPAM files
opam lint --strict *.opam
find packages -iname opam -exec opam lint --strict '{}' '+'

opam --version

opam exec -- satyrographos install

opam uninstall "$SNAPSHOT"

FAILED_PACKAGES=failed.pkgs
: > "$FAILED_PACKAGES"
SUCCEEDED_PACKAGES=succeeded.pkgs
: > "$SUCCEEDED_PACKAGES"

# Test install/uninstall regardress if it's a PR
if true ; then
    echo "Test updated packages"

    eval $(opam config env)

    sed -i.bak -e '/^# Package List$/,/^# Package List End$/d' "$SNAPSHOT".opam
    opam update

    git remote -v
    git branch -v

    git fetch origin master:master

    git branch -v

    export OPAMYES=1
    git diff --name-status master... -- packages/ | sed -e '/^D/d' -e 's/^\w*\s//' -e '/^packages\//!d' -e 's!\([^/]*/\)\{2\}!!' -e 's!/.*!!' | sort | uniq \
        | while read PACKAGE ; do
            PACKAGE_NAME="${PACKAGE%%.*}"
            SATYSFI_PACKAGE="satysfi.$(opam show -f version satysfi)"

            case "$PACKAGE_NAME" in
                satyrographos-*)
                    declare -a PACKAGES_AND_OPTIONS=('--strict' '--with-test' "$PACKAGE")
                    SKIP_OCAML_MISMATCH=1
                    SKIP_SATYSFI_MISMATCH=1
                    ;;
                *)
                    declare -a PACKAGES_AND_OPTIONS=('--strict' '--with-test' "$SATYSFI_PACKAGE" "$SNAPSHOT" "$PACKAGE")
                    SKIP_OCAML_MISMATCH=
                    SKIP_SATYSFI_MISMATCH=1
            esac

            if ! opam install --json=opam-output.json --dry-run --unlock-base "${PACKAGES_AND_OPTIONS[@]}"
            then
                echo "Assuming dependency does not meet. Skipping"
                echo "$PACKAGE: skipped: dependency" >> "$SUCCEEDED_PACKAGES"
                continue

                if [ -n "$SKIP_SATYSFI_MISMATCH" ] && jq -e '.conflicts["causes"] | index("No available version of satysfi satisfies the constraints")' opam-output.json
                then
                    echo "Dependency does not meet. Skipping"
                    echo "$PACKAGE: skipped: satysfi-dependency" >> "$SUCCEEDED_PACKAGES"
                    continue
                else
                    echo "$PACKAGE: dependency" >> "$FAILED_PACKAGES"
                    continue
                fi
            fi

            if ! opam install --json=opam-output.json --dry-run "${PACKAGES_AND_OPTIONS[@]}"
            then
                if [ -n "$SKIP_OCAML_MISMATCH" ]
                then
                    echo "Dependency on OCaml does not meet. Skipping"
                    echo "$PACKAGE: skipped: ocaml-dependency" >> "$SUCCEEDED_PACKAGES"
                    continue
                else
                    echo "$PACKAGE: ocaml-dependency" >> "$FAILED_PACKAGES"
                    continue
                fi
            fi

            if ! opam install "${PACKAGES_AND_OPTIONS[@]}"
            then
                echo "$PACKAGE: install" >> "$FAILED_PACKAGES"
                continue
            elif ! opam exec -- satyrographos install
            then
                echo "$PACKAGE: satyrographos" >> "$FAILED_PACKAGES"
                continue
            elif ! opam uninstall "$PACKAGE"
            then
                echo "$PACKAGE: uninstall" >> "$FAILED_PACKAGES"
            fi

            echo "$PACKAGE: success" >> "$SUCCEEDED_PACKAGES"
        done
    else
        echo "Non pull request"
fi

if [ -s "$SUCCEEDED_PACKAGES" ] ; then
    sed -e 's/^/- /' -e "1iSucceeded packages:" "$SUCCEEDED_PACKAGES" 1>&2
fi
if [ -s "$FAILED_PACKAGES" ] ; then
    sed -e 's/^/- /' -e "1iFailed packages:" "$FAILED_PACKAGES" 1>&2
    exit 1
fi
# vim: set et fenc=utf-8 ff=unix sts=0 sw=8 ts=4 :
