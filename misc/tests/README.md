# Tests for form.yml processing

```
ruby misc/tests/run_tests.rb            # smoke tests over every documented sample
ruby misc/tests/test_script_patterns.rb # unit tests for the script-line patterns
```

## Smoke tests

`run_tests.rb` first executes `extract_samples.rb`, which extracts every
`form.yml` sample from `docs/application.html` into `samples/` (one
directory per sample, named `<N>_<section id>` where N is the sample's
position in the docs, e.g. `1_number`, `21_set`). The documentation is the
source of truth: `samples/` is
regenerated on every run, so the tests always reflect the current docs. A few
documentation blocks are fragments (an alternative `options:` list, the
`script:`/`submit:` sections, the `header:` section, and an ERB conditional);
`extract_samples.rb` wraps those into complete samples.

Each sample in `samples/` and each app in `sample_apps/` is then run through
the form generators in `lib/form.rb` and checked for:

1. YAML (or ERB + YAML) parses,
2. the `form:` section passes the same validations as `run.rb`,
3. HTML generation raises no exception and is non-empty,
4. every widget key appears as an element id in the generated HTML,
5. the generated JavaScript is syntactically valid (`node --check`;
   skipped if node is not installed).

`*.yml.erb` samples are rendered with `@OC_DIR_NAME == "Slurm"` so that
conditional samples take their branch.

These are smoke tests: they guarantee that every documented sample builds
cleanly, but they do not exercise browser-side behavior (clicking a widget
and observing the Dynamic Form Widget's effect). Test that layer in a real
browser.

## Script-line pattern tests

`test_script_patterns.rb` covers `output_script_js()`, which turns each line of
a `script:` template into the pattern that lets the browser patch that line in
place and read it back into the widgets (see section 5.5 of
`docs/application.html`). It checks:

1. which lines get a capture regex, which are registered for placement only,
   which are literal, and which are not registered at all,
2. that each generated regex, run against a rendered line, captures the text
   the widgets would have written,
3. the `zeropadding()` round trip — pad a value the way the browser does, match
   it, strip the padding, and compare with the original,
4. that `keys` stay aligned with the capture groups.

Unlike the smoke tests it needs no samples and no node/jsc, so it runs on its
own in well under a second.
