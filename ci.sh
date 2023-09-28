#!/bin/bash

# Environmental variables
# SNAPSHOT: Package name of the current Satyrographos Repo snapshot
# COMMENT_FILE: File to output results
# ABORT_IMMEDIATELY: Imdediately abort when installation fails
# SKIP_OLDEST_DEPS: Skip building against oldest dependencies
# SKIP_REVERSE_DEPS: Skip building against reverse dependencies
# WORKAROUND_OPAM_BUG_5132: Skip integrity check against OPAM
# WORKAROUND_OPAM_BUG_STRICT: Don't use --strict option (See https://github.com/ocaml/opam-repository/pull/21959#discussion_r943873612)

set -exo pipefail

TEMPORARY_WORK_DIR=$(mktemp -dt "ci.sh.XXXXXXXXXX")

export OPAMVERBOSE=1

FAILED_PACKAGES=failed.pkgs
: > "$FAILED_PACKAGES"
SUCCEEDED_PACKAGES=succeeded.pkgs
: > "$SUCCEEDED_PACKAGES"

case "$(opam --version)" in
    2.0.*|2.1.*)
        echo "Enable workaround for OPAM Bug #5132"
        WORKAROUND_OPAM_BUG_5132=1
        ;;
esac

TIMESTAMP_DEADLINE_WORKAROUND_OPAM_BUG_STRICT=$(date -d 2022-09-01 +%s)
TIMESTAMP_NOW=$(date +%s)
if [ $TIMESTAMP_DEADLINE_WORKAROUND_OPAM_BUG_STRICT -ge $TIMESTAMP_NOW ] ; then
    echo "Enable workaround for an OPAM Bug related to --strict"
    WORKAROUND_OPAM_BUG_STRICT=1
fi

case "$(ocamlc --version)" in
    4.1[1-2].*)
        # OCaml optimizer may produce code that require extremely large stack size.
        # See https://github.com/ocaml/ocaml/issues/9839
        ulimit -s unlimited
esac

OCAML_PACKAGE="ocaml.$(opam show --color=never -f version ocaml)"

if [ -n "$SKIP_OLDEST_DEPS" ] || ! opam install --yes opam-0install
then
    echo "Skipping oldest-deps check"
    SKIP_OLDEST_DEPS=1
else
    SKIP_OLDEST_DEPS=
fi

cat_to_comment () {
    if [ -n "$COMMENT_FILE" ]
    then
        cat "$@" | tee -a "$COMMENT_FILE"
    else
        cat "$@"
    fi
}

check_opam_integrity () {
    if [ -n "$WORKAROUND_OPAM_BUG_5132" ]
    then
        echo "Skip OPAM integrity check"
        return 0
    fi

    if find "$(opam var prefix --color=never)/.opam-switch/install" -iname 'satysfi-*.changes' -exec grep -e ^'contents-changed:' '{}' '+'
    then
        echo "OPAM misdetected file creation as modification"
        exit 1
    fi
}

check_satyrographos_integrity () {
    if [ -n "$WORKAROUND_OPAM_BUG_5132" ]
    then
        echo "Workaround OPAM Bug #5132"
        opam exec -- satyrographos install $(opam list --color=never --short --installed 'satysfi-*' | sed -e 's/^satysfi-/-l /')
        return $?
    fi

    opam exec -- satyrographos install
}

opam_install_dry_run () {
    local OPAM_INSTALL_RETURN_STATUS
    check_opam_integrity
    # Workaround https://github.com/ocaml/opam/issues/5132
    mkdir -p "$TEMPORARY_WORK_DIR/opam"
    rsync -v "$(opam var prefix --color=never)/.opam-switch/install/" "$TEMPORARY_WORK_DIR/opam/install"
    opam install --dry-run "$@"
    OPAM_INSTALL_RETURN_STATUS=$?
    rsync -v "$TEMPORARY_WORK_DIR/opam/install/" "$(opam var prefix --color=never)/.opam-switch/install"
    check_opam_integrity

    return $OPAM_INSTALL_RETURN_STATUS
}

install_oldest_deps () {
    opam install opam-0install && opam install $(opam exec -- opam-0install --prefer-oldest "$@" | tr ' ' '\n' | sed -n -e '/^satyrographos\./p' -e '/^satysfi\./p' -e '/^satysfi-/p')
}

check_reverse_deps () {
    opam list --repo=satyrographos-local --all-version --short --depends-on="$1" | while read PACKAGE ; do
        if ! opam install "$1" "$PACKAGE"
        then
            echo "Revdep check failed: $1 for $PACKAGE"
            return 1
        fi
    done
}

# Test install/uninstall regardress if it's a PR
if true ; then
    echo "Test updated packages"

    eval $(opam config env)

    git --no-pager remote -v
    git --no-pager branch -va

    # export OPAMPRECISETRACKING=1 OPAMDEBUGSECTIONS="TRACK ACTION" OPAMDEBUG=-1
    export OPAMYES=1
    git diff --name-status origin/master... -- packages/ | sed -e '/^D/d' -e 's/^\w*\s//' -e '/^packages\//!d' -e 's!\([^/]*/\)\{2\}!!' -e 's!/.*!!' | sort | uniq \
        | while read PACKAGE ; do
            # Reset env
            if [ -n "$ABORT_IMMEDIATELY" ] && [ -s "$FAILED_PACKAGES" ]
            then
                sed -e 's/^/- /' -e "1i#### Failed packages\n" "$FAILED_PACKAGES" | cat_to_comment 1>&2
                exit 1
            fi

            # Reset env
            opam install "$SNAPSHOT"

            PACKAGE_NAME="${PACKAGE%%.*}"
            SATYSFI_PACKAGE="satysfi.$(opam show --color=never -f version satysfi)"

            case "$PACKAGE_NAME" in
                satyrographos-*)
                    declare -a PACKAGES_AND_OPTIONS=('--with-test' "$PACKAGE")
                    SKIP_OCAML_MISMATCH=1
                    SKIP_SATYSFI_MISMATCH=1
                    ;;
                *)
                    declare -a PACKAGES_AND_OPTIONS=('--with-test' "$PACKAGE")
                    SKIP_OCAML_MISMATCH=
                    SKIP_SATYSFI_MISMATCH=1
            esac
            if [ -z "$WORKAROUND_OPAM_BUG_STRICT" ] ; then
                PACKAGES_AND_OPTIONS+=('--strict')
            fi

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
            elif ! check_satyrographos_integrity || ! check_opam_integrity
            then
                echo "$PACKAGE: satyrographos" >> "$FAILED_PACKAGES"
                continue
            elif [ -z "$SKIP_REVERSE_DEPS" ] && ! check_reverse_deps || ! check_opam_integrity
            then
                echo "$PACKAGE: reverse-deps" >> "$FAILED_PACKAGES"
                continue
            elif [ -z "$SKIP_OLDEST_DEPS" ] && ! install_oldest_deps "$PACKAGE" "$SATYSFI_PACKAGE" "$OCAML_PACKAGE" || ! check_opam_integrity
            then
                echo "$PACKAGE: install-with-oldest-deps" >> "$FAILED_PACKAGES"
                continue
            elif [ -z "$SKIP_OLDEST_DEPS" ] && ! check_satyrographos_integrity
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
    sed -e 's/^/- /' -e "1i#### Succeeded packages\n" "$SUCCEEDED_PACKAGES" | cat_to_comment 1>&2
fi
if [ -s "$FAILED_PACKAGES" ] ; then
    sed -e 's/^/- /' -e "1i#### Failed packages\n" "$FAILED_PACKAGES" | cat_to_comment 1>&2
    exit 1
fi
# vim: set et fenc=utf-8 ff=unix sts=0 sw=4 ts=4 :
