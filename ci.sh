#!/bin/bash

# Environmental variables
# SNAPSHOT: Package name of the current Satyrographos Repo snapshot
# ABORT_IMMEDIATELY: Imdediately abort when installation fails
# SKIP_OLDEST_DEPS: Skip building against oldest dependencies

set -exo pipefail

TEMPORARY_WORK_DIR=$(mktemp -dt "ci.sh.XXXXXXXXXX")

export OPAMVERBOSE=1

FAILED_PACKAGES=failed.pkgs
: > "$FAILED_PACKAGES"
SUCCEEDED_PACKAGES=succeeded.pkgs
: > "$SUCCEEDED_PACKAGES"

OCAML_PACKAGE="ocaml.$(opam show --color=never -f version ocaml)"

if [ -n "$SKIP_OLDEST_DEPS" ] || ! opam install opam-0install
then
    echo "Skipping oldest-deps check"
    SKIP_OLDEST_DEPS=1
else
    SKIP_OLDEST_DEPS=
fi

check_opam_integrity () {
    if find "$(opam var prefix)/.opam-switch/install" -iname 'satysfi-*.changes' -exec grep -e ^'contents-changed:' '{}' '+'
    then
        echo "OPAM misdetected file creation as modification"
        exit 1
    fi
}

opam_install_dry_run () {
	check_opam_integrity
    mkdir -p "$TEMPORARY_WORK_DIR/opam"
    rsync -av "$(opam var prefix)/.opam-switch/install/" "$TEMPORARY_WORK_DIR/opam/install"
    opam install --dry-run "$@"
    rsync -av "$TEMPORARY_WORK_DIR/opam/install/" "$(opam var prefix)/.opam-switch/install"
	check_opam_integrity
}

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
            if [ -n "$ABORT_IMMEDIATELY" ] && [ -s "$FAILED_PACKAGES" ]
            then
                sed -e 's/^/- /' -e "1iFailed packages:" "$FAILED_PACKAGES" 1>&2
                exit 1
            fi

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

            if ! opam_install_dry_run --json=opam-output.json --cli=2.1 --update-invariant "${PACKAGES_AND_OPTIONS[@]}" "$SATYSFI_PACKAGE"
            then
                echo "Dependency does not meet."
                cat opam-output.json

                if [ -n "$SKIP_SATYSFI_MISMATCH" ] && opam_install_dry_run --json=opam-output.json --cli=2.1 --update-invariant "${PACKAGES_AND_OPTIONS[@]}"
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

            if ! opam_install_dry_run --json=opam-output.json "${PACKAGES_AND_OPTIONS[@]}"
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

            if ! opam install --deps-only "${PACKAGES_AND_OPTIONS[@]}"
            then
                echo "$PACKAGE: dep-install" >> "$FAILED_PACKAGES"
                continue
            elif ! opam install "${PACKAGES_AND_OPTIONS[@]}" || ! check_opam_integrity
            then
                echo "$PACKAGE: install" >> "$FAILED_PACKAGES"
                continue
            elif ! opam exec -- satyrographos install || ! check_opam_integrity
            then
                echo "$PACKAGE: satyrographos" >> "$FAILED_PACKAGES"
                continue
            elif [ -z "$SKIP_OLDEST_DEPS" ] && ! ( opam install opam-0install && opam install $(opam exec -- opam-0install --prefer-oldest "$PACKAGE" "$SATYSFI_PACKAGE" "$OCAML_PACKAGE") ) || ! check_opam_integrity
            then
                echo "$PACKAGE: install-with-oldest-deps" >> "$FAILED_PACKAGES"
                continue
            elif [ -z "$SKIP_OLDEST_DEPS" ] && ! opam exec -- satyrographos install
            then
                echo "$PACKAGE: satyrographos-with-oldest-deps" >> "$FAILED_PACKAGES"
                continue
            elif ! opam uninstall "$PACKAGE" || ! check_opam_integrity
            then
                echo "$PACKAGE: uninstall" >> "$FAILED_PACKAGES"
            fi

            echo "$PACKAGE: success" ${SKIP_OLDEST_DEPS:+skip-oldest-deps} >> "$SUCCEEDED_PACKAGES"
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
# vim: set et fenc=utf-8 ff=unix sts=0 sw=4 ts=4 :
