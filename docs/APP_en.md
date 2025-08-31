## Overview
1. Enter the directory name to store all applications in `apps_dir` in `./conf.yml.erb`. Here, set it to `apps_dir: ./apps`.
2. Create a directory for applications under `./apps/`. If the application name is `test`, create `./apps/test`.
3. Create the configuration files `form.yml` and `manifest.yml` in `./apps/test`. To write the files in Embedded Ruby format, rename the files to `form.yml.erb` and `manifest.yml.erb`, respectively.
- `./apps/test/form.yml`: Settings for the web form
- `./apps/test/manifest.yml`: Description of the application

## Settings of form.yml
The `form.yml` is composed of three main keys: `form`, `header`, `script`, `check` and `submit`.
Each key defines main widgets, header widgets, a job script, validation of a job script, and pre-processing when submitting a job script, respectively.
`form` and `script` are required fields, but `header`, `check` and `submit` can be omitted.

The following figure shows the scope of `form`, `header` and `script` sections.
A job script is generated from `form`, `header`, and `script` sections.
However, `header` is optional, and if omitted, `./lib/header.yml.erb` is used instead (in most cases, there is no need to define `header`).
Note that the application name in the upper left is the scope of `manifest.yml`.

<img src="img/sections.png" width="800" alt="Sections">

The `check` section performs validation of the widget inputs before job submission.
The `submit` section defines the pre-processing when submitting a job to the job scheduler.

### widget: number
Displays a numeric input field.
In the example below, `nodes` is the variable name for the widget.
The `label` is the displayed name,
`value` is the default value,
`min` and `max` set the range, and `step` determines the increment.
The `required` key specifies whether the input is mandatory, and `help` provides a tooltip below the input field.
The `script` section specifies how the input value will appear in the job script.
The `#{nodes}` in the `script` will be replaced with the input value.

```
form:
  nodes:
    widget:   number
    label:    Number of nodes (1 - 128)
    value:    4
    min:      1
    max:      128
    step:     1
    required: false
    help:     The larger the number, the longer the wait time.
    
script: |
  #SBATCH --nodes=#{nodes}
```

You can display multiple numeric input fields.
For instance, specifying `size` will indicate the number of input fields, with each item defined as an array.
In the `script` section, `#{time_1}` and `#{time_2}` will be replaced with the respective values entered in the fields.

```
form:
  time:
    widget: number
    label:  [ Maximum run time (0 - 24 h), Maximum run time (0 - 59 m) ]
    size:   2
    value:  [  1,  0 ]
    min:    [  0,  0 ]
    max:    [ 24, 59 ]
    step:   [  1,  1 ]
    
script: |
  #SBATCH --time=#{time_1}:#{time_2}:00
```
![Label](img/label1.png)

If `label` is not an array, a single-line label can be provided.
The same applies to `help`.

```
form:
  time:
    widget: number
    label:  Maximum run time (0 - 24 h, 0 - 59 m)
    size:   2
    value:  [  1,  0 ]
    min:    [  0,  0 ]
    max:    [ 24, 59 ]
    step:   [  1,  1 ]
```
![Label](img/label2.png)

To pad a number in a job script with zeros, use the zeropadding function.
The first argument is the key, and the second argument is the number.
If the number of digits is less than the number specified in the second argument, the missing digits will be filled with "0".

```
form:
  time:
    widget: number
    label:  [ Maximum run time (0 - 24 h), Maximum run time (0 - 59 m) ]
    size:   2
    value:  [  1,  0 ]
    min:    [  0,  0 ]
    max:    [ 24, 59 ]
    step:   [  1,  1 ]

script: |
  #SBATCH --time=#{time_1}:#{zeropadding(time_2, 2)}:00
```
![Zero Padding](img/zeropadding.png)

You can also write a label for each item and a long label on one line.
Write the long label as the first element of the array format, and write the second element in array format.

```
form:
  time:
    widget: number
    label:  [Maximum run time, [0 - 24 h, 0 - 59 m]]
    size:   2
    value:  [  1,  0 ]
    min:    [  0,  0 ]
    max:    [ 24, 59 ]
    step:   [  1,  1 ]
```
![Label](img/label3.png)

If you want to change the label of the job script (default is "Script Content"), set `label` for `script`.
In that case, write the job script in `content`.

```
script:
  label: Job Script
  content: |
    #SBATCH --nodes=#{nodes}
```

In the `check` section, a Ruby script and the function `oc_assert(condition, message)` ensures validation.
This function outputs a `message` and terminates if `condition` is `false`.
In the example below, if a total time exceeding 24 hours is entered,
an error message will be displayed when the "Submit" button is clicked,
preventing the script from being submitted.
To refer to a `form` variable, write the variable name after the @ sign, and all variables are treated as strings.

The `check` section also supports the following special variables:
- @OC_APP_NAME : Application name defined in `name` of `manifest.yml`
- @OC_APP_PATH : The path to the application where `form.yml` is stored (e.g. `/Slurm`)
- @OC_SCRIPT_LOCATION : `Script Location` defined in `header`
- @OC_CLUSTER_NAME : `Cluster name` defined in `header` (This is only available when `cluster` is defined in `./conf.yml.erb`)
- @OC_SCRIPT_NAME : `Script Name` defined in `header`
- @OC_JOB_NAME : `Job Name` defined in `header`

```
form:
  time:
    widget: number
    label:  [ Maximum run time (0 - 24 h), Maximum run time (0 - 59 m) ]
    size:   2
    value:  [  1,  0 ]
    min:    [  0,  0 ]
    max:    [ 24, 59 ]
    step:   [  1,  1 ]

script: |
  #SBATCH --time=#{time_1}:#{time_2}:00

check: |
  time_1 = @time_1.to_i
  time_2 = @time_2.to_i
  message = "Exceeded Time"
  oc_assert(time_1 != 24 || time_2 == 0, message)
```

In the `submit` section, a shell script is written to process before the job is submitted.
When referencing `form` variables, use `#{...}` in the same way as `form`.
The environment variable `OC_SUBMIT_OPTIONS` allows you to set additional options to the job submission command.
After this process is executed, the command to submit the job script (for example, sbatch #{OC_SUBMIT_OPTIONS} -J #{OC_JOB_NAME} #{OC_SCRIPT_NAME}) is executed.

```
submit: |
  #!/bin/bash

  cd #{OC_SCRIPT_LOCATION}
  mv #{OC_SCRIPT_NAME} param.conf
  genjs_ct param.conf > #{OC_SCRIPT_NAME}
  OC_SUBMIT_OPTIONS="-n 1"
```

### widget: text
Displays a text input field.

```
form:
  comment:
    widget: text
    value: test
    label: Comment

script: |
  #SBATCH --comment=#{comment}
```

You can also display multiple text input fields in a single line.

```
form:
  option:
    widget: text
    value: [ --comment=, test ]
    label: [ option, argument ]
    size: 2

script: |
  #SBATCH #{option_1}#{option_2}
```

### widget: email
Similar to `widget: text`, but validates the input to ensure it follows the email format when the "Submit" button is clicked.

```
form:
  email:
    widget: email
    label:  Email
    
script: |
  #SBATCH --mail-user=#{email}
```

### widget: select
Displays a dropdown menu.
The `options` key specifies the choices as an array.
Each option's first element is the display name in the dropdown.
In the `script` section, `#{partition}` is replaced with the second element of the selected option.

```
form:
  partition:
    widget: select
    label: Partition
    value: Large Queue
    options:
      - [ Small Queue, small ]
      - [ Large Queue, large ]
      
script: |
  #SBATCH --partition=#{partition}
```

For multi-dimensional values,
`options` can use an array for the second element.
In this example, `#{package_1}` and `#{package_2}` are replaced with the respective first and second values of the selected array.
This format is also available for `widget: multi_select`, `widget: radio` and `widget: checkbox`.

```
form:
  package:
    widget: select
    label: Select package
    options:
      - [A, [packageA, a.out]]
      - [B, [packageB, b.out]]

script: |
  module load #{package_1}
  mpiexec #{package_2}
```

### widget: multi_select
Displays an input field where multiple items can be selected.
The `options` key specifies the available choices.

```
form:
  load_modules:
    widget: multi_select
    label: Add modules
    value: mpi/mpich-x86_64
    options:
      - [mpi/mpich-x86_64, mpi/mpich-x86_64]
      - [mpi/openmpi-x86_64, mpi/openmpi-x86_64]
      - [nvhpc/24.3, nvhpc/24.3]
      - [nvhpc/24.5, nvhpc/24.5]
      - [nvhpc/24.7, nvhpc/24.7]

script: |
  module load #{load_modules}
```

If `mpi/mpich-x86_64` and `nvhpc/24.7` are selected, the job script will display them on separate lines:

```
module load mpi/mpich-x86_64
module load nvhpc/24.7
```

To display selected items in a single line, set the `separator` key with a delimiter.

```
form:
  load_modules:
    widget: multi_select
    label: Add modules
    value: mpi/mpich-x86_64
    separator: " "
    options:
      - [mpi/mpich-x86_64, mpi/mpich-x86_64]
      - [mpi/openmpi-x86_64, mpi/openmpi-x86_64]
      - [nvhpc/24.3, nvhpc/24.3]
      - [nvhpc/24.5, nvhpc/24.5]
      - [nvhpc/24.7, nvhpc/24.7]
      
script: |
  module load #{load_modules}
```

This will generate:

```
module load mpi/mpich-x86_64 nvhpc/24.7
```

Multiple default values can also be set using an array format.

```
form:
  load_modules:
    widget: multi_select
    label: Add modules
    value: [mpi/mpich-x86_64, nvhpc/24.7]
    options:
      - [mpi/mpich-x86_64, mpi/mpich-x86_64]
      - [mpi/openmpi-x86_64, mpi/openmpi-x86_64]
      - [nvhpc/24.3, nvhpc/24.3]
      - [nvhpc/24.5, nvhpc/24.5]
      - [nvhpc/24.7, nvhpc/24.7]
```

### widget: radio
Displays a radio button.
It is similar to `widget: select`,
but the `direction` key can specify the button layout.
Setting `direction: horizontal` arranges the buttons horizontally,
while omitting it defaults to a vertical layout.

```
form:
  jupyter:
    widget: radio
    label: Jupyter
    direction: horizontal
    value: Jupyter Lab
    options:
      - [ Jupyter Lab,      jupyterlab ]
      - [ Jupyter Notebook, jupyter    ]

script: |
  module load #{jupyter}
```

### widget: checkbox
Displays checkboxes.
If you set `required` in array format as follows, it will set whether each item is required.

```
form:
  mail_option:
    label: Mail option
    widget: checkbox
    direction: horizontal
    value: [ Fail of job,  When the job is requeued ]
    required: [true, false, true, false, false]
    options:
      - [ Beginning of job execution, BEGIN   ]
      - [ End of job execution,       END     ]
      - [ Fail of job,                FAIL    ]
      - [ When the job is requeued,   REQUEUE ]
      - [ All,                        ALL     ]

script: |
  #SBATCH --mail-type=#{mail_option}
```

When `required` is a single boolean value (e.g., true), at least one checkbox must be selected before submission.

```
form:
  mail_option:
    label: Mail option
    widget: checkbox
    direction: horizontal
    value: [ Fail of job,  When the job is requeued ]
    required: true
    options:
      - [ Beginning of job execution, BEGIN   ]
      - [ End of job execution,       END     ]
      - [ Fail of job,                FAIL    ]
      - [ When the job is requeued,   REQUEUE ]
      - [ All,                        ALL     ]

script: |
  #SBATCH --mail-type=#{mail_option}
```

You can set the `separator` similar to `widget: multi_select`, and you can set the `direction` similar to `widget: radio`.

### widget: path
Displays a field for entering the path of a file or directory on the server where Open Composer is running.
The default value of value is ${HOME}.
The `show_files` key toggles whether files are displayed (default: true).
The `favorites` key sets shortcut paths.

```
form:
  working_dir:
    widget: path
    label: Working Directory
    value: /work
    show_files: false
    favorites:
      - /fs/ess
      - /fs/scratch

script: |
  cd #{working_dir}
```

The functions `dirname(FILE_PATH)` and `basename(FILE_PATH)` can be used in the script to extract the directory or file name from a path.

```
form:
  input_file:
    widget: path
    label: Input file

script: |
  cd #{dirname(input_file)}
  mpiexec ./#{basename(input_file)}
```

### Dynamic form widget
You can dynamically change the settings of other widgets based on the selected option in `select`, `radio`, and `checkbox` widgets..

### Minimum, maximum, step, label, and value settings
Specifies `set-(min|max|step|label|value|required|help)-(KEY)[_(num|1st element in options)]:(VALUE)` from the third element and onward of each `options` array.

In the following example, if you select `Medium` for `node_type`, the label and maximum value for `cores` will be `Number of Cores (1-8)` and `8`.

```
form:
  node_type:
    widget: select
    label: Node Type
    options:
      - [ Small,  small ]
      - [ Medium, medium, set-label-cores: Number of Cores (1-8),  set-max-cores: 8  ]
      - [ Large,  large,  set-label-cores: Number of Cores (1-16), set-max-cores: 16 ]

  cores:
    widget: number
    label: Number of Cores (1-4)
    value: 1
    min: 1
    max: 4
    step: 1
```

For `number`, `text`, or `email` widgets with multiple input fields,
you can specify the target input field using `_(num)`.
In the following example,
if you select `GPU` for `node_type`,
the label and maximum value of the first `time` input field will be `Maximum run time hours (0 - 24)` and `24`.

```
form:
  node_type:
    widget: select
    label: Node Type
    options:
      - [ 'Standard', '' ]
      - [ 'GPU',      '', set-label-time_1: Maximum run time (0 - 24h), set-max-time_1: 24 ]

  time:
    widget:  number
    label:   [ Maximum run time (0 - 72 h), Maximum run time (0 - 59 m) ]
    size:    2
    value:   [  1,  0 ]
    max:     [ 72, 59 ]
    min:     [  0,  0 ]
    step:    [  1,  1 ]
```

For `select`, `radio`, and `checkbox` widgets,
use `1st element in options` to specify the target option.
In the following example, when you select `GPU` for `node_type`, `Enable GPU` for `enable_gpu` is checked.

```
form:
  node_type:
    widget: select
    label: Node Type
    options:
      - [ 'Standard', '' ]
      - [ 'GPU',      '', set-value-enable_gpu: Enable GPU ]

  enable_gpu:
    widget: checkbox
    options:
      - [ Enable GPU, gpu ]
```

### Disable or enable widgets and options
Specifies `[disable|enable]-(KEY)[-(1st element in options)][_num]` for the third element and onward of each `options` array.

In the following example,
when `Fugaku` is selected for `cluster`,
the `GPU` option for `node_type` and the `cuda_ver` widget will be disabled.
If a key is disabled, its line in `script` will also be deleted.

```
form:
  cluster:
    widget: select
    label:  Cluster system
    options:
      - [ Fugaku,  fugaku, disable-node_type-GPU, disable-cuda_ver ]
      - [ Tsubame, tsubame ]

  node_type:
    widget: select
    label:  Node type
    options:
      - [ Standard, standard ]
      - [ GPU,      gpu      ]

  cuda_ver:
    widget: number
    label: CUDA version
    value: 12
    min: 12
    max: 14

script: |
  module load system/#{node_type}
  module load cuda/#{cuda_ver}
```

### Hide a widget
Specifies `[hide|show]-(KEY)` for the third element and onward of each `options` array.
In the following example,
checking `hide_advanced_options` will hide `comment`.
Unlike disabling, it only hides the widget of that key, and does not affect the `script` line.
The `indent` creates an indent on the left side of a web form.
You can enter a number from 1 to 5, and the higher the number, the larger the indent width.
```
form:
  hide_advanced_option:
    widget: checkbox
    options:
      - [ 'Hide advanced option', '', hide-comment ]

  comment:
    widget: text
    label: Comment
    indent: 1

script: |
  #SBATCH --comment=#{comment}
```

In the following example, `comment` will be displayed if `show_advanced_options` is checked.

```
form:
  show_advanced_options:
    widget: checkbox
    options:
      - [ 'Show advanced option', '', show-comment ]

  comment:
    widget: text
    label: Comment
    indent: 1

script: |
  #SBATCH --comment=#{comment}
```

### Combining widgets with available options

| Widget | label<br>value<br>required<br>help<br>indent |  options<br>(Dynamic Form Widget) | size  | separator | direction | min<br>max<br>step| show_files<br>favorites |
| ---- | ---- | ----  | ---- | ---- | ---- |  ----  |  ---- |
| number | ○ | | ○ | | | ○| | 
| text<br>email | ○ |  | ○ | | |  | | 
| select | ○ |  ○ (○) | | | | | | 
| multi_select | ○ | ○ | | ○|  | |
| radio | ○ |  ○ (○)| | |○ | | | 
| checkbox | ○ |  ○ (○) | | ○| ○|  | | 
| path | ○ |  | | || | ○ | 

Only `options` is required, the others are optional.

### Hide job script

You can hide your job script in the text area on the right side.
Use the special variable `SCRIPT_CONTENT` and the `hide-` of the Dynamic Form Widget in the following way.
Note that the filename is `form.yml.erb`, since it is an ERB.

```
form:
  script_content:
    widget: checkbox
    value: "Hide script content"
    options:
      - ["Hide script content", "", hide-<%= SCRIPT_CONTENT %>]
```

<img src="img/hide-script.png" width="800" alt="Hide script">

If you want to hide the job script without displaying the checkbox, set `hide-` to the checkbox itself.

```
form:
  script_content:
    widget: checkbox
    value: "Hide script content"
    options:
      - ["Hide script content", "", hide-<%= SCRIPT_CONTENT %>, hide-script_content]
```

### Settings of header
The same widgets can be used in `form.yml`.
However, widgets with the same names as those defined in lib/headers.yml.erb must be defined.

The following example adds a new widget `script_content`, which hides the job script, to the defined widgets (`_script_location` and `_script`).
If `cluster` is defined in `./conf.yml.erb`, `_cluster_name` must also be defined.

```
header:
  _script_location:
    widget:     path
    value:      <%= Dir.home %>
    label:      Script Location
    show_files: false
    required:   true

  _script:
    widget:   text
    size :    2
    label:    [Script Name, Job Name]
    value:    [job.sh, ""]
    required: [true, false]

  script_content:
    widget: checkbox
    value: "Hide script content"
    options:
      - ["Hide script content", "", hide-<%= SCRIPT_CONTENT %>]
```

<img src="img/hide-script-header.png" width="800" alt="Hide script in header">

## Settings of manifest.yml
Describes your application. Here is a sample:

```
name: Gaussian
category: Quantum Chemistry
icon: icon.png
description: |
  [Gaussian](https://gaussian.com) is a general purpose computational chemistry software package.
related_app:
  - OVITO: ovito.png
  - GrADS: bi-airplane-fill
  - ImageJ
```

- name: Application name (If this key is omitted, the directory name will be used instead)
- category: Category name
- icon: Path to image file for icon. URL, [Bootstrap icon](https://icons.getbootstrap.com/), or [Font Awesome icon](https://fontawesome.com) is also possible. For Bootstrap icons, write `icon: bi-airplane-fill`. For Font Awesome icons, write `icon: fa-solid fa-gear`.
- description: Description of the application
- related_app: When performing post-processing, specify an application registered in Open OnDemand. The specified application will be displayed on the history page. As with `icon:`, you can specify icon images, etc. If no image is specified, the image registered in Open OnDemand will be used.

## Supplementary information
- Widget names can only contain alphanumeric characters and underscores (`_`). Numbers and underscores cannot start the name.
  - The same rule applies to the directory name in which the application is saved.
  - Note that widget names ending with an underscore and a number (e.g. `nodes_1`) may conflict when referencing the value of a widget with the `size` attribute.
  - When defining `header` in `form.yml`, the widget names beginning with underscores (`_script_location` and `_script`) used in `lib/header.yml.erb` can be used.
- If there is no second element in `options`, the first element is used instead.
- In `script`, if a variable used in a line does not have a value, the line is not displayed. However, if you add a colon to the beginning of the variable (e.g. `#{:nodes}` or `#{basename(:input_file)}`), the line will be output even if the variable does not have a value.
- The order of processing that Open Composer performs before submitting a job script to the job scheduler is as follows.
  1. The "Submit" button is clicked in the application page
  2. Execute the script written in `check` in `form.yml` (if `check` exists)
  3. Execute the script written in `submit` in `form.yml` (if `submit` exists)
  4. Submit the job script to the job scheduler
