# Satyrographos Repo

[![Build Status](https://github.com/na4zagin3/satyrographos-repo/workflows/CI/badge.svg?branch=master)](https://github.com/na4zagin3/satyrographos-repo/actions?query=workflow%3ACI)

*We also have a web interface, [Satyrographos Package Index](https://satyrographos-packages.netlify.app/) (thanks to @matsud224).*

This is a custom OPAM repository for [Satyrographos], a package manager for [SATySFi].

You can add this repository into your OPAM by running the following command.

```sh
# This repository depends on containts in satysfi-external repo
opam repository add satysfi-external https://github.com/gfngfn/satysfi-external-repo.git
opam repository add satyrographos https://github.com/na4zagin3/satyrographos-repo.git
```

## Contributing

We welcome contributions! If you notice a problem of *packaging*, then send a PR or write an issue here. If it's a problem of the content of package itself, then refer to its repository.

To submit a PR for your project in GitHub, run the following command in your repository.

```sh
git tag -a <version> # For example, git tag -a v0.1
git push origin <version>
opam publish --repo=na4zagin3/satyrographos-repo
```

Maintainers may ask contributors to update files for automation tests.

## For development versions

We have `satyrographos-repo-alpha` repository which has development versions, especially the next versions of SATySFi and those depends on them.

See https://github.com/na4zagin3/satyrographos-repo-alpha/tree/main#readme for more details.

## License

All the metadata contained in this repository are licensed under the [CC0 1.0 Universal license](https://creativecommons.org/publicdomain/zero/1.0/) or any later version (i.e., `CC0-1.0+` license in [SPDX License Identifier](https://spdx.org/licenses/)).

### Reference

* ["Repository format"](https://opam.ocaml.org/doc/Manual.html#Repository-format)
* "Managing Repositories" of ["OPAM: A Package Management System for OCaml Developer Manual (version 1.2.1)"](http://opam.ocaml.org/doc/manual/dev-manual.html)
* https://github.com/ocaml/opam-repository
* Some other OPAM repos
    * https://github.com/ocamllabs/advanced-fp-repo
    * https://github.com/coq/opam-coq-archive


  [SATySFi]: https://github.com/gfngfn/SATySFi
  [Satyrographos]: https://github.com/na4zagin3/satyrographos
