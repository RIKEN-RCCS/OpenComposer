# Smoke tests for form.yml processing

```
ruby misc/tests/run_tests.rb
```

`run_tests.rb` first executes `extract_samples.rb`, which extracts every
`form.yml` sample from `docs/application.html` into `samples/` (one
directory per sample, named `<N>_<section id>` where N is the sample's
position in the docs, e.g. `1_number`, `21_set`). The documentation is the
source of truth: `samples/` is
regenerated on every run, so the tests always reflect the current docs. A few
documentation blocks are fragments (an alternative `options:` list, the
`script:`/`submit:` sections, the `header:` section, and an ERB conditional);
`extract_samples.rb` wraps those into complete samples. Fragment sections the
docs no longer contain are skipped rather than treated as an error.

Each sample in `samples/` and each app in `sample_apps/` is then run through
the form generators in `lib/form.rb` and checked for:

1. YAML (or ERB + YAML) parses,
2. the `form:` section passes the same validations as `run.rb`,
3. HTML generation raises no exception and is non-empty,
4. every widget key appears as an element id in the generated HTML,
5. the generated JavaScript is syntactically valid (`node --check`, falling
   back to macOS's bundled `jsc`; skipped if neither is available).

`*.yml.erb` samples are rendered with `@OC_DIR_NAME == "Slurm"` so that
conditional samples take their branch.

These are smoke tests: they guarantee that every documented sample builds
cleanly, but they do not exercise browser-side behavior (clicking a widget
and observing the Dynamic Form Widget's effect). Test that layer in a real
browser.
