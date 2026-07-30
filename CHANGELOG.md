# Changelog

## [Unreleased]
### Add
- Add an OOD-integrated (embedded) mode that renders Open Composer inside Open OnDemand's own navbar and footer, via a reverse-proxy dashboard initializer under `ood_integration/` and without an iframe.
- Add an All Templates page (`/all_templates`) listing every template as one flat list, including applications hidden from the index page.
- Add custom templates: save the current form values as a reusable template, then rename, re-describe, delete or reorder them from the index page.
- Add a "Load or Create a Script from Disk" file browser that opens an existing batch script in the generic scheduler form with its location and name pre-filled.
- Add New Script and New Custom Template pickers for choosing which application to start from.
- Add a Nodes page listing the cluster's compute nodes with their state, CPU, memory and generic resources, with one dynamically discovered column per GRES type.
- Add a `module_load` widget: a dropdown of every available version of an environment module, which rewrites the existing `module load` line in place so surrounding script lines are preserved.
- Add a `dependent_module_select` widget whose module list follows the value of another widget.
- Add `remember_last` to `select` widgets, restoring the user's previous choice from browser storage.
- Add script-to-form parsing, so editing the script pane, or opening a job from the history page, reconstructs the form from the script's scheduler directives.
- Add an empty-script submission warning (`empty_script_warning`).
- Add a Job Efficiency panel to the history page (`history_efficiency`), reporting wall time, CPU, memory and, for GPU jobs, GPU utilization and GPU memory.
- Add output and error columns to the history page, with an in-page file viewer.
- Add "Cancel All Jobs", "Delete All History" and "Refresh" actions to the history page, plus per-job cancellation with progress reporting.
- Add optional SSH key provisioning on submit (`ensure_ssh_key`), disabled by default.
- Add a `modules_list_url` setting for the module catalog behind the module widgets.
- Add `home_format`, `category_badge_colors`, `accent_color`, `body_text_color`, `gpu_memory` and `favicon` settings.
- Add `hidden`, `documentation` and `tags` manifest keys, and allow `category` to be given as a list.

### Changed
- Use `sacct` as the source of truth on the history page, so jobs submitted outside Open Composer also appear, with their script fetched live.
- Move the generic per-scheduler script templates to `generic_apps_dir`, reachable at `/_generic/<directory>` and used as the fallback when an application's `form.yml` is missing.
- Replace the hard-coded accent palette and GPU memory capacities with settings, so a site can be restyled without editing a view.
- Reorganize `conf.yml.erb.sample` into ten numbered sections, matching section 2 of `docs/install.html`.
- Pass `scheduler_env` to every scheduler command, not only to submission, cancellation and status queries.
- Extend the `form.yml` smoke tests to cover the new widgets, and fall back to macOS's bundled `jsc` when `node` is unavailable.

### Fixed
- Anchor the `enable-<key>-<option>` regex, so an option name that is a prefix of another can be targeted alone.
- Gate the Shell Access navbar link on `show_shell_access`, and hide it when no login node is configured.
- Give `OC_HISTORY_PARTITION` and `OC_HISTORY_SUBMISSION_TIME` real column definitions instead of rendering permanently empty columns.
- Export `sge_root` on every request, so the history and nodes pages run `qstat`/`qacct`/`qhost` with `SGE_ROOT` set.
- List an application under each of its categories when `category` is given as a list.
- Pass `dependent_module_select` values to the `check` section, which previously saw `nil`.
- Expand a hidden section only on a directive line unique to it when loading a script, so shared directives no longer tick unrelated toggles.

## [2.0.2] - 2026-07-27
### Add
- Support the Dynamic Form Widget in `multi_select` widgets.
- Add smoke tests (`misc/tests/run_tests.rb`) that build every form.yml sample in the documentation and `sample_apps/`.

### Changed
- Sort applications on the index page using natural order, so numeric prefixes such as `10_App` sort after `2_App` instead of before.

## [2.0.1] - 2026-07-10
### Add
- Allow custom values to be entered in multi_select widgets, in addition to the predefined suggestions.
- Add a `scheduler_env` setting in conf.yml to customize environment variables passed to scheduler commands.
- Add a `copy_environment` setting for Slurm to control whether `--export=ALL` or `--export=NONE` is used.

### Changed
- Disable spellcheck on generated form inputs and filter inputs.
- Shorten the Slurm configless host example in the documentation and sample conf.yml.
- Prefix internal history columns with underscores to avoid conflicts with user-defined history fields.

### Fixed
- Fix a modal that could fail to show job details on the history page in [31](https://github.com/RIKEN-RCCS/OpenComposer/issues/31).
- Fix history not updating immediately after canceling a job.
- Fix caching conflicts caused by internal history keys.
- Fix a SyntaxError that could break the Script Content editor layout when multiple multi_select widgets retained submitted values after a failed job submission.

## [2.0.0] - 2026-05-11
### Add
- Add side-by-side syntax highlighting overlays for the script and submit textareas.
- Add configurable `highlight_theme` and `directive_color` settings for history/script highlighting.
- Add advanced history search options for date range, AND/OR matching, and field selection.
- Add history search elapsed-time output next to the entry count.

### Changed
- Change history storage from PStore to SQLite with automatic migration from legacy `.db` files.
- Expand history search to index all stored job values, including Job Details and Job Script contents.
- Improve history search highlighting so it follows AND/OR search terms and the selected field.

## Fix
- Fix initialization error in Dynamic Form Widget

## [1.9.0] - 2026-03-20
### Add
- A warning will be displayed before manual changes to the script and submit sections are deleted.
- Support OC_ROUNDING_ROUND, OC_ROUNDING_FLOOR, and OC_ROUNDING_CEIL in calc().
- Local Development is added in install manual.

### Changed
- RACK is used for development.
- Improve README to match Appverse documentation standard in [18](https://github.com/RIKEN-RCCS/OpenComposer/issues/28).

## [1.8.0] - 2025-12-26
### Add
- Add the function to define multiple login_nodes and ssh_wrappers in conf.yml in [25](https://github.com/RIKEN-RCCS/OpenComposer/discussions/25).
- Add calc function in [20](https://github.com/RIKEN-RCCS/OpenComposer/pull/20).
- History page items can be freely changed in [19](https://github.com/RIKEN-RCCS/OpenComposer/pull/19).
- Add failed job status in [19](https://github.com/RIKEN-RCCS/OpenComposer/pull/19).
- The cancel/delete modal and job script modal on the history page can be resized in [19](https://github.com/RIKEN-RCCS/OpenComposer/pull/19).
- Add a variable @OC_DIR_NAME.

### Changed
- Change clusters from cluster in conf.yml (It is an incompatible change).
- Change related_apps from related_apps in manifest.yml (It is an incompatible change).
- Changed dirname and basename to work the same as linux commands.
- Change a variable OC_SCRIPT_CONTENT from SCRIPT_CONTENT.

### Fixed
- Do nothing if expr returns an error.

## [1.7.0] - 2025-11-06
### Add
- The function only saves job scripts.
- The function allows users to view and edit preprocessing.

### Changed
- Manual format changed from Markdown to HTML.

### Fixed
- An error occurs when you first open the History page in [18](https://github.com/RIKEN-RCCS/OpenComposer/pull/18).
- An issue where variables could not be referenced in the submit and check sections.
- An error where the separator was not reflected when using an array as the second argument in the options of checkbox and multi_select widgets.
- An error that disabled elements could not be referenced on the initial screen.

## [1.6.0] - 2025-10-19
### Add
- The function for zeropadding.
- The function to output log.
- The custom PBS Pro scheduler for Miyabi.

### Changed
- Change the manual format from Markdown to HTML.
- Change "cancel job" from "delete job" in history page.
- The name of the page from Top Page to Home Page.

### Fixed
- The initial value was not set correctly when the value was a number.
- Consolidate querying both running and history jobs in PBS Pro in [9](https://github.com/RIKEN-RCCS/OpenComposer/pull/9).
- PBS Pro qstat bug in [8](https://github.com/RIKEN-RCCS/OpenComposer/pull/8).

## [1.5.0] - 2025-05-08
### Add
- Add highlights to filtered results in history page.
- Support multiple clusters.

### Changed
- Filter in history page searches all job information.

### Fixed
- Sanitization for XSS.

## [1.4.0] - 2025-04-08

### Added
- Support to set a main label and a sub-label.
- Support to hide job scripts.
- Dynamic Form Widget is also enabled in the header.
- Add icons such as Open OnDemand to the navigation bar.
- Add an effect for submit button.
- Add a function oc_assert() which can be used in form.yml.

### Changed
- For slurm, remove init_bash and added --export=NONE to the sbatch option.
- For slurm, PBSpro and Fujitsu TCS, increase the amount of verbose output.
- On the history page, when you hover the cursor over the image of a visualization app, the name of the application is displayed.
- On the history page, adjust the amount of information depending on the window width.
- Change width when script content is hidden from 800px to 960px.
- Adjust the amount of information displayed in the history depending on the window width.
- Change the command from Cancel Job to Delete Job.
- Display error messages more clearly in form.

### Fixed
- A reference so that it works even if the destination of related_app in manuscript is a link.

## [1.3.0] - 2025-02-12

### Added
- Support Grid Engine job scheduler.
- It is possible to define headers for each application.
- For pre-processing, submit section in form.yml is added. And delete submit.yml.
- Added the ability to change the script label.
- The path widget can specify the directory one level above.
- It is possible to define headers for each application.

### Changed
- Change path selector modal overflow behavior in [1](https://github.com/RIKEN-RCCS/OpenComposer/pull/1)
- To speed up the history page, update the status only for the job IDs that are displayed.
- The separator option enables output without spaces.
- To prevent elements that are initially hidden from appearing for just a moment, make them visible after all loading is complete.

### Fixed
- Fixed behavior of the path widget with or without a slash at the end of a directory.

## [1.2.0] - 2025-01-20

### Added
- Support PBS job scheduler.
- Add bin_overrides in conf.yml.erb.
- Add a utility misc/read_yml_erb.rb.

### Changed
- login_node in conf.yml.erb has been made optional.
- Simplify `ident` parameter.
- When a job scheduler error occurs, output stdout as well as stderr.
- Get the job submission date and time from a Ruby function, not from the scheduler.

### Fixed
- Fixed a mistake in the application name link on the form.
- Element with disabled is considered unchecked.
- When the selected option in select widget becomes disabled by dynamic form widget, the non-disabled option is selected.
- Fixed an issue where the disable- and hide- options for radio and checkbox widgets did not work properly when there was more than one option.

## [1.1.0] - 2025-01-09

### Added
- Added `ident` parameter in the web form.
- Enabled setting related applications.
- Added support for Font Awesome icons.
- Included English documents.
- Introduced a function to specify an application directory.
- Added an option to include the value of "Job Name" in the header as part of the job submission command.

### Changed
- Divided the manual into sections for creating web forms and using Open Composer.
- Extended the inquiry period for completed Fujitsu_TCS jobs to 365 days.
- Improved error handling: when job submission fails, the same page reloads with the failed parameters pre-filled.
- Updated manual examples: replaced `job_name` examples with `comment` examples to reduce confusion.
- Made labels bold for better visibility.
- Made application names in forms bold.
- Ensured that changes in header values do not update `JOB_SCRIPT_CONTENTS`.

### Fixed
- Fixed the issue with loading the bash environment when executing `pjsub`/`sbatch` commands.
- Resolved the issue where `public/no_image_square.jpg` could not be displayed.

### Security
- Applied URL encoding for special characters on the history page to enhance security.

## [1.0.0] - 12-11-2024
First release.
