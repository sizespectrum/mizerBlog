# mizer blog

This repository contains the source for the mizer blog at
<https://blog.mizer.sizespectrum.org>. The site is built with Quarto and the
rendered HTML is committed in `docs/` for GitHub Pages.

## Repository layout

- `_quarto.yml` configures the Quarto website and sets `docs/` as the output
  directory.
- `index.qmd` is the blog index page.
- `about.qmd` is the about page.
- `posts/` contains the source files for blog posts.
- `posts/_metadata.yml` applies common post settings, including the Disqus
  include.
- `mizer.css` contains the site styling.
- `filters/inline-code-links.lua` links inline R function names to their
  documentation when possible.
- `_freeze/` contains Quarto's committed freeze cache for executed documents.
- `docs/` contains generated site output and is what GitHub Pages serves.
- `.quarto/` is Quarto's local working directory and should not be committed.

Edit the source files, not the generated HTML in `docs/`. The `docs/` files are
updated by `quarto render`.

## Prerequisites

Install the Quarto CLI, then install the R packages used by the posts and the
inline-code link filter:

```r
install.packages(c(
  "mizer", "downlit", "knitr", "rmarkdown", "tidyverse",
  "plotly", "magrittr", "patchwork", "assertthat", "Rcpp", "remotes"
))
remotes::install_github("sizespectrum/mizerExperimental")
```

There is no `renv` lockfile at present, so if a render reports another missing
package, install it in your local R library and render again.

## Preview locally

From the repository root, run:

```bash
quarto preview
```

Quarto will start a local web server and print the URL. Keep that process
running while you edit posts; the preview refreshes as files change.

## Render the site

To build the full site into `docs/`, run:

```bash
quarto render
```

The project has `execute.freeze: true` in `_quarto.yml`, so a full project
render uses the top-level `_freeze/` cache and does not re-execute code blocks.
Commit the source changes, the generated changes under `docs/`, and any
corresponding changes under the top-level `_freeze/` directory. Do not commit
`.quarto/`, even though it may contain its own local `.quarto/_freeze/` copy.

If you intentionally want to refresh the computations for one post, render that
post directly, for example:

```bash
quarto render posts/2025-04-02-age-in-mizer/age-in-mizer.Rmd
```

Directly rendering a single post always executes its code and updates the frozen
results for that post.

Run `quarto render` before publishing so that the index, feed, search data and
site map in `docs/` are also updated.

## Add or update a post

1. Create a directory under `posts/`, normally named with the publication date
   and a short slug, for example `posts/2026-05-13-my-post/`.
2. Add the post source as `.qmd`, `.Rmd` or `.md`. Existing posts are mostly
   `.Rmd`, but Quarto can render all three.
3. Put post-specific images and bibliography files next to the post source, and
   refer to them with relative paths.
4. Add YAML front matter at the top of the post. A typical post starts like:

```yaml
---
title: "My post title"
description: |
  A short summary used by listings, feeds and social previews.
author:
  - name: Your Name
date: 2026-05-13
preview: images/preview.png
---
```

The `preview` field is optional. If you use it, the path is relative to the post
directory. For posts with R code, use a setup chunk to load the packages needed
by that post. Do not use the old R Markdown `output: distill::distill_article`
block in new posts. Shared Quarto options live in
`posts/_metadata.yml`; add a post-level `format: html:` block only for settings
that differ from those defaults, for example:

```yaml
format:
  html:
    number-sections: true
```

## Publish

1. Render the site with `quarto render`.
2. Review the Git diff. Expect changes in `docs/` as well as the edited source
   files.
3. Commit both the source files and the generated `docs/` output.
4. Push to the `master` branch on GitHub.

The repository is configured for GitHub Pages to serve the committed `docs/`
directory. The custom domain is recorded in `docs/CNAME`.
