## How to install Open Composer
Open Composer runs on [Open OnDemand](https://openondemand.org/).
Save Open Composer in your Open OnDemand application directory: `/var/www/ood/apps/sys/`.

```
# cd /var/www/ood/apps/sys/
# git clone https://github.com/RIKEN-RCCS/OpenComposer.git
```

## Open Composer configuration
Create `./conf.yml.erb` with reference to `./conf.yml.erb.sample`.
The `apps_dir` is required and either `scheduler` or `cluster` is required.

| Item name | Setting |
| ---- | ---- |
| apps_dir | Application directory |
| scheduler | Job scheduler (`slurm`, `pbspro`, `sge` or `fujitsu_tcs`) |
| cluster | Cluster properties |
| data_dir | Directory where submitted job information is stored (Default is `${HOME}/composer`) |
| login_node | Login node when you launch the Open OnDemand web terminal |
| ssh_wrapper | Commands for using the job scheduler of another node using SSH |
| bin | PATH of commands of job scheduler |
| bin_overrides | PATH of each command of job scheduler |
| sge_root | Directory for the Grid Engine root (SGE_ROOT) |
| footer | Text in the footer |
| thumbnail_width | Width of thumbnails for each application on the home page |
| navbar_color | Color of navigation bar |
| dropdown_color | Color of dropdown menu |
| footer_color | Color of footer |
| category_color | Background color of the home page category |
| description_color | Background color of the application description in the application page |
| form_color | Background color of the text area in the application page |

### Setting bin_overrides (Optional)
If the job scheduler is `slurm`, set `sbatch`, `scontrol`, `scancel`, and `sacct` as follows.

```
bin_overrides:
  sbatch:   "/usr/local/bin/sbatch"
  scontrol: "/usr/local/bin/scontrol"
  scancel:  "/usr/local/bin/scancel"
  sacct:    "/usr/local/bin/sacct"
```

If the job scheduler is `pbspro`, set `qsub`, `qstat`, and `qdel` as follows.

```
bin_overrides:
  qsub:   "/usr/local/bin/qsub"
  qstat: "/usr/local/bin/qstat"
  qdel:  "/usr/local/bin/qdel"
```

If the job scheduler is `sge`, set `qsub`, `qstat`, `qdel`, and `qacct` as follows.

```
bin_overrides:
  qsub:   "/usr/local/bin/qsub"
  qstat: "/usr/local/bin/qstat"
  qdel:  "/usr/local/bin/qdel"
  qacct: "/usr/local/bin/qacct"
```

If the job scheduler is `fujitsu_tcs`, set `pjsub`, `pjstat`, and `pjdel` as follows.

```
bin_overrides:
  pjsub:  "/usr/local/bin/pjsub"
  pjstat: "/usr/local/bin/pjstat"
  pjdel:  "/usr/local/bin/pjdel"
```

### Setting cluster (Optional)
Set this when using multiple job schedulers.
The `name` and `scheduler` are required and set the cluster name and scheduler respectively.
Other scheduler related settings (`bin`, `bin_overrides`, `sge_root`) are also possible.
Note that when setting `cluster`, `scheduler`, `bin`, `bin_overrides`, `sge_root` cannot be set outside of `cluster`.

```
cluster:
  - name: "fugaku"
    scheduler: "fujitsu_tcs"
  - name: "prepost"
    scheduler: "slurm"
    bin_overrides:
      sbatch:   "/usr/local/bin/sbatch"
```

## Registration for Open OnDemand by administrator
When you save Open Composer to `/var/www/ood/apps/sys/`, the Open Composer icon will be displayed on the Open OnDemand page.
If it is not displayed, check `./manifest.yml`.

You can also display Open Composer applications on the Open OnDemand page.
For example, if you want to display an application `./sample_apps/apps/Slurm/`,
create a directory with the same name in the Open OnDemand application directory (`# mkdir /var/www/ood/apps/sys/Slurm`).
Then, create the following Open OnDemand configuration file `manifest.yml` in that directory.

```
# cat /var/www/ood/apps/sys/Slurm/manifest.yml
---
name: Slurm
url: https://example.net/pun/sys/OpenComposer/Slurm
```

## Registration for Open OnDemand by general user
You can also install Open Composer with general user privileges.
However, the [App Development](https://osc.github.io/ood-documentation/latest/how-tos/app-development/enabling-development-mode.html) feature in Open OnDemand needs to be enabled in advance by an administrator.

Select "My Sandbox Apps (Development)" under "</> Develop" in the navigation bar. (Note that if your web browser window size is small, it will display "</>" instead of "</> Develop".)

<img src="img/navbar.png" width="400" alt="Navbar">

Click "New App".

<img src="img/newapp.png" width="400" alt="New App">

Click "Clone Existing App".

<img src="img/clone.png" width="400" alt="Clone an existing app">

Enter any name in "Directory name" (here we enter OpenComposer), enter "[https://github.com/RIKEN-RCCS/OpenComposer.git](https://github.com/RIKEN-RCCS/OpenComposer.git)" in "Git remote", and click "Submit".

<img src="img/new_repo.png" width="800" alt="New repository">

Click "Launch Open Composer".

<img src="img/bundle.png" width="800" alt="Bundle Install">
