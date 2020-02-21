# Satyrographos Repo

[![Build Status](https://travis-ci.com/na4zagin3/satyrographos-repo.svg?branch=master)](https://travis-ci.com/na4zagin3/satyrographos-repo)

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

Maintainers may ask contributors to add packages to `.travis.yml` for automation tests.

## Development version

We have `develop` branch which has development versions, especially SATySFi.
Execute the following command to use them.

```sh
# This repository depends on containts in satysfi-external repo
opam repository add satyrographos-develop https://github.com/na4zagin3/satyrographos-repo.git#develop
```

To submit a PR to `devel` branch, specify `-b` option.

```sh
opam publish --repo=na4zagin3/satyrographos-repo -b develop
```

### Reference

* ["Repository format"](https://opam.ocaml.org/doc/Manual.html#Repository-format)
* "Managing Repositories" of ["OPAM: A Package Management System for OCaml Developer Manual (version 1.2.1)"](http://opam.ocaml.org/doc/manual/dev-manual.html)
* https://github.com/ocaml/opam-repository
* Some other OPAM repos
    * https://github.com/ocamllabs/advanced-fp-repo
    * https://github.com/coq/opam-coq-archive


  [SATySFi]: https://github.com/gfngfn/SATySFi
  [Satyrographos]: https://github.com/na4zagin3/satyrographos
