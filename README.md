## Overview

Open Composer is a web application to generate batch job scripts and submit batch jobs for HPC clusters on [Open OnDemand](https://openondemand.org/).

- Installation ([English](./docs/INSTALL_en.md) | [Japanese](./docs/INSTALL_ja.md))
- Settings of application ([English](./docs/APP_en.md)  | [Japanese](./docs/APP_ja.md))
- Manual ([English](./docs/MANUAL_en.md) | [Japanese](./docs/MANUAL_ja.md))

## Disscussions
- https://github.com/RIKEN-RCCS/OpenComposer/discussions

## Supported job scheduler
- Slurm
- PBS Pro
- Grid Engine
- Fujitsu_TCS

## Sample configuration
- https://github.com/RIKEN-RCCS/composer_fugaku
- https://github.com/RIKEN-RCCS/composer_rccs_cloud

## Demo
https://github.com/user-attachments/assets/0eee0b62-9364-465a-ae1e-7d412c1c9de9

## Tips
When developing Open Composer on Open OnDemand with general user privileges,
it is recommended to run Open Composer in development mode.
When an error occurs, its cause will be displayed in the web browser.
Please edit `run.sh` as follows.

```
#set :environment, :production
set :environment, :development
```

## Reference
- [SupercomputingAsia 2025](https://sca25.sc-asia.org/), Singapore, Mar., 2025 [[Poster](https://mnakao.net/data/2025/sca.pdf)]
- [The 197th HPC Research Symposium](https://www.ipsj.or.jp/kenkyukai/event/arc251hpc197.html), Fukuoka, Japan, Dec., 2024 [[Paper](https://mnakao.net/data/2024/HPC197.pdf)] [[Slide](https://mnakao.net/data/2024/HPC197-slide.pdf)] (Japanese)
