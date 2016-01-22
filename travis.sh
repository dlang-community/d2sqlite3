#!/usr/bin/env bash

set -ueo pipefail

if [ ! -z "${COVERAGE:-}" ]; then
    dub fetch doveralls
    dub test -b unittest-cov
    dub run doveralls
else
    dub test
fi

if [ ! -z "${GH_TOKEN:-}" ]; then
    # build docs, TODO: replace w/ ddoxTool in dub.json
    DFLAGS='-c -o- -Df__dummy.html -Xfdocs.json -version=SQLITE_ENABLE_COLUMN_METADATA' dub build
    dub fetch scod
    dub run scod -- filter --min-protection=Protected --only-documented docs.json
    dub run scod -- generate-html --navigation-type=ModuleTree docs.json docs
    pkg_path=$(dub list | sed -n 's|.*scod.*: ||p')
    rsync -ru "$pkg_path"public/ docs/

    # push docs to gh-pages branch
    cd docs
    git init
    git config user.name 'Travis-CI'
    git config user.email '<>'
    git add .
    git commit -m 'Deployed to Github Pages'
    git push --force --quiet "https://${GH_TOKEN}@github.com/${TRAVIS_REPO_SLUG}" master:gh-pages
fi
