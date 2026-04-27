#!/bin/bash

# Environmental variables
# SNAPSHOT: Package name of the current Satyrographos Repo snapshot
# COMMENT_FILE: File to output results
# ABORT_IMMEDIATELY: Imdediately abort when installation fails
# SKIP_OLDEST_DEPS: Skip building against oldest dependencies
# SKIP_REVERSE_DEPS: Skip building against reverse dependencies
# WORKAROUND_OPAM_CHANGES_FALSE_POSITIVE: Skip opam .changes integrity checks for known false positives
# WORKAROUND_OPAM_BUG_STRICT: Don't use --strict option (See https://github.com/ocaml/opam-repository/pull/21959#discussion_r943873612)

set -exo pipefail

TEMPORARY_WORK_DIR=$(mktemp -dt "ci.sh.XXXXXXXXXX")

export OPAMVERBOSE=1

FAILED_PACKAGES=failed.pkgs
: > "$FAILED_PACKAGES"
SUCCEEDED_PACKAGES=succeeded.pkgs
: > "$SUCCEEDED_PACKAGES"

has_installed_jbuilder () {
    opam list --installed --short --color=never 2>/dev/null | grep -qx jbuilder
}

case "$(opam --version)" in
    2.0.*|2.1.*|2.2.*|2.3.*|2.4.*)
        echo "Enable workaround for opam .changes false positives on older opam"
        WORKAROUND_OPAM_CHANGES_FALSE_POSITIVE=1
        echo "Enable workaround for #655"
        WORKAROUND_OPAM_BUG_STRICT=1
        ;;
    *)
        if has_installed_jbuilder
        then
            echo "Enable workaround for opam .changes false positives with installed jbuilder"
            WORKAROUND_OPAM_CHANGES_FALSE_POSITIVE=1
        fi
        ;;
esac

TIMESTAMP_DEADLINE_WORKAROUND_OPAM_BUG_STRICT=$(date -d 2022-09-01 +%s)
TIMESTAMP_NOW=$(date +%s)
if [ $TIMESTAMP_DEADLINE_WORKAROUND_OPAM_BUG_STRICT -ge $TIMESTAMP_NOW ] ; then
    echo "Enable workaround for an OPAM Bug related to --strict"
    WORKAROUND_OPAM_BUG_STRICT=1
fi

OCAML_PACKAGE="ocaml.$(opam show --color=never -f version ocaml)"
OPAM_0INSTALL_PACKAGE="opam-0install>=0.5.1"

if [ -n "$SKIP_OLDEST_DEPS" ] || ! opam install --yes "$OPAM_0INSTALL_PACKAGE"
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

dump_opam_integrity_debug () {
    local OPAM_SWITCH_INSTALL_DIR
    local CHANGES_FILE
    local MATCHED_CHANGES_FILES
    OPAM_SWITCH_INSTALL_DIR="$(opam var prefix --color=never)/.opam-switch/install"

    echo "==== OPAM integrity debug ===="
    echo "Context: ${1:-unknown}"
    echo "opam version: $(opam --version)"
    echo "opam root: $(opam var root --color=never)"
    echo "opam prefix: $(opam var prefix --color=never)"
    echo "repositories:"
    opam repository list --color=never || true
    echo "installed dune/jbuilder/opam packages:"
    opam list --installed --columns=name,version --color=never 2>/dev/null | grep -E "^(dune|jbuilder|opam|opam-format|opam-file-format)\b" || true

    if [ ! -d "$OPAM_SWITCH_INSTALL_DIR" ]
    then
        echo "install dir missing: $OPAM_SWITCH_INSTALL_DIR"
        return 0
    fi

    echo "install dir: $OPAM_SWITCH_INSTALL_DIR"
    MATCHED_CHANGES_FILES="$(find "$OPAM_SWITCH_INSTALL_DIR" -iname '*.changes' -exec grep -l -e '^contents-changed:' '{}' + | sort || true)"
    if [ -z "$MATCHED_CHANGES_FILES" ]
    then
        echo "no matching *.changes files found during debug dump"
        echo "all *.changes files:"
        find "$OPAM_SWITCH_INSTALL_DIR" -iname '*.changes' | sort || true
        return 0
    fi

    echo "matched *.changes files:"
    printf '%s\n' "$MATCHED_CHANGES_FILES"

    while read -r CHANGES_FILE
    do
        [ -n "$CHANGES_FILE" ] || continue
        echo "---- $CHANGES_FILE ----"
        cat "$CHANGES_FILE" || true
    done <<EOF_CHANGES
$MATCHED_CHANGES_FILES
EOF_CHANGES
}
check_opam_integrity () {
    local CONTEXT
    CONTEXT=${1:-unknown}
    if [ -n "$WORKAROUND_OPAM_CHANGES_FALSE_POSITIVE" ]
    then
        echo "Skip OPAM integrity check"
        return 0
    fi

    local OPAM_SWITCH_INSTALL_DIR
    OPAM_SWITCH_INSTALL_DIR="$(opam var prefix --color=never)/.opam-switch/install"
    if [ ! -d "$OPAM_SWITCH_INSTALL_DIR" ]
    then
        return 0
    fi

    if find "$OPAM_SWITCH_INSTALL_DIR" -iname '*.changes' -exec grep -e ^'contents-changed:' '{}' '+'
    then
        dump_opam_integrity_debug "$CONTEXT"
        echo "OPAM misdetected file creation as modification"
        exit 1
    fi
}

check_satyrographos_integrity () {
    if [ -n "$WORKAROUND_OPAM_CHANGES_FALSE_POSITIVE" ]
    then
        echo "Work around opam .changes false positives with installed jbuilder"
        opam exec -- satyrographos install $(opam list --color=never --short --installed 'satysfi-*' | sed -e 's/^satysfi-/-l /')
        return $?
    fi

    opam exec -- satyrographos install
}

opam_install_dry_run () {
    local OPAM_INSTALL_RETURN_STATUS
    local OPAM_INSTALL_BACKUP_DIR
    local OPAM_SWITCH_INSTALL_DIR
    mkdir -p "$TEMPORARY_WORK_DIR/opam"
    OPAM_INSTALL_BACKUP_DIR=$(mktemp -dt "ci.sh.opam-install.XXXXXXXXXX" -p "$TEMPORARY_WORK_DIR/opam")
    OPAM_SWITCH_INSTALL_DIR="$(opam var prefix --color=never)/.opam-switch/install"
    check_opam_integrity "before-opam-install-dry-run"
    # Preserve install metadata around dry-runs when the false-positive workaround is enabled
    if [ -d "$OPAM_SWITCH_INSTALL_DIR" ]
    then
        rsync -a "$OPAM_SWITCH_INSTALL_DIR/" "$OPAM_INSTALL_BACKUP_DIR/"
    fi
    opam install --dry-run "$@"
    OPAM_INSTALL_RETURN_STATUS=$?
    mkdir -p "$OPAM_SWITCH_INSTALL_DIR"
    rsync -a "$OPAM_INSTALL_BACKUP_DIR/" "$OPAM_SWITCH_INSTALL_DIR/"
    check_opam_integrity "after-opam-install-dry-run"

    return $OPAM_INSTALL_RETURN_STATUS
}

install_oldest_deps () {
    local OLDEST_DEPS
    local OPAM_0INSTALL_OUTPUT
    local OPAM_0INSTALL_STATUS
    # Do not upgrade opam-0install here: doing so can remove the installed snapshot.
    OPAM_0INSTALL_OUTPUT=$(opam exec --set-root --set-switch -- opam-0install --prefer-oldest "$@" 2>&1)
    OPAM_0INSTALL_STATUS=$?
    if [ "$OPAM_0INSTALL_STATUS" -ne 0 ]
    then
        echo "$OPAM_0INSTALL_OUTPUT"
        if echo "$OPAM_0INSTALL_OUTPUT" | grep -q 'more recent than this version of opam'
        then
            echo "Skipping oldest-deps check: installed opam-0install cannot read this opam root"
            return 2
        fi
        return "$OPAM_0INSTALL_STATUS"
    fi
    OLDEST_DEPS=$(echo "$OPAM_0INSTALL_OUTPUT" | tr ' ' '\n' | sed -n -e '/^satyrographos\./p' -e '/^satysfi\./p' -e '/^satysfi-/p')
    if [ -z "$OLDEST_DEPS" ]
    then
        echo "opam-0install produced no satysfi/satyrographos packages"
        return 1
    fi
    opam install $OLDEST_DEPS
}

check_reverse_deps () {
    local CHECKED_REVERSE_DEPS=0
    local SKIPPED_REVERSE_DEPS=0

    while read REVERSE_DEP_PACKAGE ; do
        case "$REVERSE_DEP_PACKAGE" in
            satyrographos-snapshot-*)
                echo "Skipping snapshot reverse dependency: $REVERSE_DEP_PACKAGE"
                SKIPPED_REVERSE_DEPS=$((SKIPPED_REVERSE_DEPS + 1))
                continue
                ;;
        esac
        if ! opam_install_dry_run --json=opam-output.json "$1" "$REVERSE_DEP_PACKAGE"
        then
            echo "Skipping reverse dependency with unsatisfied constraints: $REVERSE_DEP_PACKAGE"
            SKIPPED_REVERSE_DEPS=$((SKIPPED_REVERSE_DEPS + 1))
            continue
        elif ! opam install "$1" "$REVERSE_DEP_PACKAGE"
        then
            echo "Revdep check failed: $1 for $REVERSE_DEP_PACKAGE"
            echo "$CHECKED_REVERSE_DEPS $SKIPPED_REVERSE_DEPS" > "$REVERSE_DEPS_STATUS_FILE"
            return 1
        fi
        echo "Checked reverse dependency: $1 for $REVERSE_DEP_PACKAGE"
        CHECKED_REVERSE_DEPS=$((CHECKED_REVERSE_DEPS + 1))
    done < <(opam list --color=never --repo=satyrographos-local --all-version --short --depends-on="$1")

    echo "$CHECKED_REVERSE_DEPS $SKIPPED_REVERSE_DEPS" > "$REVERSE_DEPS_STATUS_FILE"
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
            PACKAGE_SKIPPED_OLDEST_DEPS=
            REVERSE_DEPS_STATUS_FILE="$TEMPORARY_WORK_DIR/reverse-deps-status"
            : > "$REVERSE_DEPS_STATUS_FILE"
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
            elif ! opam install "${PACKAGES_AND_OPTIONS[@]}" || ! check_opam_integrity "after-install"
            then
                echo "$PACKAGE: install" >> "$FAILED_PACKAGES"
                continue
            elif ! check_satyrographos_integrity || ! check_opam_integrity "after-satyrographos-install"
            then
                echo "$PACKAGE: satyrographos" >> "$FAILED_PACKAGES"
                continue
            elif { [ -z "$SKIP_REVERSE_DEPS" ] && ! check_reverse_deps "$PACKAGE"; } || ! check_opam_integrity "after-reverse-deps"
            then
                echo "$PACKAGE: reverse-deps" >> "$FAILED_PACKAGES"
                continue
            elif [ -z "$SKIP_OLDEST_DEPS" ]
            then
                set +e
                install_oldest_deps "$PACKAGE" "$SATYSFI_PACKAGE" "$OCAML_PACKAGE"
                OLDEST_DEPS_STATUS=$?
                set -e
                if [ "$OLDEST_DEPS_STATUS" -eq 2 ]
                then
                    PACKAGE_SKIPPED_OLDEST_DEPS=1
                elif [ "$OLDEST_DEPS_STATUS" -ne 0 ] || ! check_opam_integrity "after-oldest-deps"
                then
                    echo "$PACKAGE: install-with-oldest-deps" >> "$FAILED_PACKAGES"
                    continue
                elif ! check_satyrographos_integrity
                then
                    echo "$PACKAGE: satyrographos-with-oldest-deps" >> "$FAILED_PACKAGES"
                    continue
                fi
            fi

            if ! opam uninstall "$PACKAGE" || ! check_opam_integrity "after-uninstall"
            then
                echo "$PACKAGE: uninstall" >> "$FAILED_PACKAGES"
                continue
            fi

            SUCCESS_FLAGS=
            if [ -n "$SKIP_OLDEST_DEPS$PACKAGE_SKIPPED_OLDEST_DEPS" ]
            then
                SUCCESS_FLAGS="skip-oldest-deps"
            fi
            if [ -s "$REVERSE_DEPS_STATUS_FILE" ]
            then
                read CHECKED_REVERSE_DEPS SKIPPED_REVERSE_DEPS < "$REVERSE_DEPS_STATUS_FILE"
                SUCCESS_FLAGS="$SUCCESS_FLAGS checked-revdeps=$CHECKED_REVERSE_DEPS skipped-revdeps=$SKIPPED_REVERSE_DEPS"
            fi
            echo "$PACKAGE: success" $SUCCESS_FLAGS >> "$SUCCEEDED_PACKAGES"
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
