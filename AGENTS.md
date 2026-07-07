# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A [Quarto](https://quarto.org/) blog for the mizer R package, published at <https://blog.mizer.sizespectrum.org>. The rendered HTML lives in `docs/` and is served via GitHub Pages from the `master` branch.

## Key commands

**Preview locally** (live-reload dev server):

``` bash
quarto preview
```

**Full render** (builds all posts into `docs/`):

``` bash
quarto render
```

**Render a single post** (re-executes its R code and updates `_freeze/`):

``` bash
quarto render posts/<dir>/<file>.Rmd
```

Always run `quarto render` before committing so that `docs/` (index, feed, search, sitemap) is up to date.

## Freeze cache

`execute.freeze: true` in `_quarto.yml` means `quarto render` uses pre-computed results from the top-level `_freeze/` directory instead of re-running R code. Commit `_freeze/` changes alongside source changes. Do not commit `.quarto/` (the local working directory Quarto uses internally).

Rendering a single post file directly always re-executes its code and refreshes its `_freeze/` entry.

## Post format

Posts live under `posts/<YYYY-MM-DD-slug>/`. Use `.qmd`, `.Rmd`, or `.md`.

Minimal front matter:

``` yaml
---
title: "Post title"
description: |
  One-sentence summary for listings, feeds, and social previews.
author:
  - name: Author Name
date: YYYY-MM-DD
---
```

- `image: images/preview.png` (optional, relative to post directory) sets the listing thumbnail.
- Shared settings (Disqus, TOC, etc.) come from `posts/_metadata.yml` — only add `format: html:` overrides in a post if you need something different.
- Do **not** use `output: distill::distill_article` in new posts.

## Inline code linking

`filters/inline-code-links.lua` runs at render time and calls R (`downlit::autolink_url()`) to resolve inline backtick code like `` `project()` `` to documentation URLs. It resolves against mizer and base R packages. If the `Rscript` call fails it silently leaves code unlinked.

## Publishing

1.  `quarto render`
2.  Commit source files + `docs/` + any `_freeze/` changes
3.  Push to `master` — GitHub Pages serves `docs/` automatically

The custom domain is recorded in `docs/CNAME`. Do not delete that file.

## R package dependencies

No `renv` lockfile. Required packages:

``` r
install.packages(c(
  "mizer", "downlit", "knitr", "rmarkdown", "tidyverse",
  "plotly", "magrittr", "patchwork", "assertthat", "Rcpp", "remotes"
))
remotes::install_github("sizespectrum/mizerExperimental")
```

If a render fails due to a missing package, install it and re-render.
