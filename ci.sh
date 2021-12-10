#!/bin/bash

set -exo pipefail

export OPAMVERBOSE=1

FAILED_PACKAGES=failed.pkgs
: > "$FAILED_PACKAGES"
SUCCEEDED_PACKAGES=succeeded.pkgs
: > "$SUCCEEDED_PACKAGES"

# Test install/uninstall regardress if it's a PR
if true ; then
    echo "Test updated packages"

    eval $(opam config env)

    git remote -v
    git branch -va

    export OPAMYES=1
    git diff --name-status origin/master... -- packages/ | sed -e '/^D/d' -e 's/^\w*\s//' -e '/^packages\//!d' -e 's!\([^/]*/\)\{2\}!!' -e 's!/.*!!' | sort | uniq \
        | while read PACKAGE ; do
            # Reset env
            opam install "$SNAPSHOT"

            PACKAGE_NAME="${PACKAGE%%.*}"
            SATYSFI_PACKAGE="satysfi.$(opam show --color=never -f version satysfi)"

            case "$PACKAGE_NAME" in
                satyrographos-*)
                    declare -a PACKAGES_AND_OPTIONS=('--strict' '--with-test' "$PACKAGE")
                    SKIP_OCAML_MISMATCH=1
                    SKIP_SATYSFI_MISMATCH=1
                    ;;
                *)
                    declare -a PACKAGES_AND_OPTIONS=('--strict' '--with-test' "$PACKAGE")
                    SKIP_OCAML_MISMATCH=
                    SKIP_SATYSFI_MISMATCH=1
            esac

            if ! opam install --json=opam-output.json --dry-run --cli=2.1 --update-invariant "${PACKAGES_AND_OPTIONS[@]}" "$SATYSFI_PACKAGE"
            then
                echo "Dependency does not meet."
                cat opam-output.json

                if [ -n "$SKIP_SATYSFI_MISMATCH" ] && opam install --json=opam-output.json --dry-run --cli=2.1 --update-invariant "${PACKAGES_AND_OPTIONS[@]}"
                then
                    echo "Can be installed with another satysfi version. Skipping."
                    cat opam-output.json
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
