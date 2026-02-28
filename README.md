## Overview

Open Composer is a web application to generate batch job scripts and submit batch jobs for HPC clusters on [Open OnDemand](https://openondemand.org/).

Open Composer is an Open OnDemand app in the "Jobs"
category. Unlike Batch Connect interactive apps, Open Composer provides a graphical
interface for creating, previewing, editing, and submitting batch job scripts. It
supports multiple job schedulers and can be configured for different HPC applications.

- **App type:** Workflow Composer (Jobs category)
- **Latest release:** [`v1.8.0`](https://github.com/RIKEN-RCCS/OpenComposer/releases/tag/v1.8.0) (see [Changelog](https://github.com/RIKEN-RCCS/OpenComposer/blob/main/CHANGELOG.md))
- **License:** MIT (see [LICENSE file](https://github.com/RIKEN-RCCS/OpenComposer/blob/main/LICENSE))
- **Requirements:** Open OnDemand 3.0 or later.
- **Supported job schedulers:** Slurm, PBS Pro, Grid Engine, Fujitsu TCS
- **Features**
  - Graphical web interface for generating and submitting batch job scripts
  - Multi-scheduler and multi-cluster support
  - Job history page with filtering, status tracking, and job cancellation
  - Editable job script preview before submission
  - Configurable application forms via `form.yml`
  - Dynamic form widgets with conditional visibility and validation
  - Support for preprocessing steps via submit sections
  - Customizable per-application headers and labels
  - Path selector widget for file and directory selection
  - Bilingual documentation (English and Japanese)
									
## Screenshots

### Home page
  <img width="600" style="border: 1px solid #333;" alt="Home" src="https://riken-rccs.github.io/OpenComposer/docs/img/home_page.png">

### Application page
  <img width="600" style="border: 1px solid #333;" alt="Application" src="https://riken-rccs.github.io/OpenComposer/docs/img/application_page.png">

### History page
  <img width="600" style="border: 1px solid #333;" alt="History" src="https://riken-rccs.github.io/OpenComposer/docs/img/history_page.png">

## Demo
https://github.com/user-attachments/assets/0eee0b62-9364-465a-ae1e-7d412c1c9de9

## Documents

You can access the full documentation below:
<table>
  <tr>
    <td>Installation</td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/install.html" target="_blank" rel="noopener noreferrer">EN</a></td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/install_ja.html" target="_blank" rel="noopener noreferrer">JA</a></td>
  </tr>
  <tr>
    <td>Application Settings</td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/application.html" target="_blank" rel="noopener noreferrer">EN</a></td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/application_ja.html" target="_blank" rel="noopener noreferrer">JA</a></td>
  </tr>
  <tr>
    <td>User manual</td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/manual.html" target="_blank" rel="noopener noreferrer">EN</a></td>
    <td><a href="https://riken-rccs.github.io/OpenComposer/docs/manual_ja.html" target="_blank" rel="noopener noreferrer">JA</a></td>
  </tr>
</table>

### Quick start

```sh
cd /var/www/ood/apps/sys
git clone https://github.com/RIKEN-RCCS/OpenComposer.git
cd OpenComposer

# Pin to a release (recommended)
git checkout v1.8.0
```

Open Composer uses `conf.yml` for cluster and scheduler configuration and
per-application `form.yml` files to define job submission forms.

## Testing

| System      | Site        | Scheduler          | Repository |
|-------------|-------------|--------------------|------------|
| Fugaku      | RIKEN RCCS  | Fujitsu TCS, Slurm | https://github.com/RIKEN-RCCS/composer_fugaku     |
| R-CCS Cloud | RIKEN RCCS  | Slurm              | https://github.com/RIKEN-RCCS/composer_rccs_cloud |


## Contributing

For discussions, see the [GitHub Discussions](https://github.com/RIKEN-RCCS/OpenComposer/discussions).

## Troubleshooting

For bugs or feature requests, [open an issue](https://github.com/RIKEN-RCCS/OpenComposer/issues) with detailed logs and reproduction steps.

## Reference
If you use this software in your research or development work, please cite the following publication:

> Masahiro Nakao and Keiji Yamamoto. 2025. ``Open Composer: A Web-Based Application for Generating and Managing Batch Jobs on HPC Clusters''. In Proceedings of the SC '25 Workshops of the International Conference for High Performance Computing, Networking, Storage and Analysis (SC Workshops '25). Association for Computing Machinery, New York, NY, USA, 697-704. https://doi.org/10.1145/3731599.3767428

## Presentation
- [HUST: International Workshop on HPC User Support Tools](https://hust-workshop.github.io), St. Louis, USA, Nov. 2025 [[Paper](https://doi.org/10.1145/3731599.3767428)] [[Slide](https://www.mnakao.net/data/2025/HUST2025.pdf)]
- [SupercomputingAsia 2025](https://sca25.sc-asia.org/), Singapore, Mar. 2025 [[Poster](https://mnakao.net/data/2025/sca.pdf)]
- [The 197th HPC Research Symposium](https://www.ipsj.or.jp/kenkyukai/event/arc251hpc197.html), Fukuoka, Japan, Dec. 2024 [[Paper](https://mnakao.net/data/2024/HPC197.pdf)] [[Slide](https://mnakao.net/data/2024/HPC197-slide.pdf)] (Japanese)

## Known limitations

No major limitations are currently known.

## Acknowledgments

The authors thank the Open OnDemand community for providing a robust ecosystem for HPC web applications.
Development of Open Composer has been carried out at [RIKEN R-CCS](https://www.r-ccs.riken.jp/en/), with significant contributions from [RIST](https://www.rist.or.jp/ehome.html).
