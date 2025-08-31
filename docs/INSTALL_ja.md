## Open Composerのインストール方法
Open Composerは[Open OnDemand](https://openondemand.org/)上で動作します。Open ComposerをOpen OnDemandのアプリケーションディレクトリ`/var/www/ood/apps/sys/`に保存してください。

```
# cd /var/www/ood/apps/sys/
# git clone https://github.com/RIKEN-RCCS/OpenComposer.git
```

## Open Composerの設定
`./conf.yml.erb.sample`を参考にして`./conf.yml.erb`を作成してください。`apps_dir`は必須です。`scheduler`もしくは`cluster`のどちらか1つは必須です。

| 項目名 | 設定内容 |
| ---- | ---- |
| apps_dir | アプリケーションのディレクトリ |
| scheduler | 利用するスケジューラ（`slurm`、`pbspro`、`sge`、`fujitsu_tcs`） |
| cluster | クラスタの定義 |
| data_dir | 投入したジョブの情報のディレクトリ（デフォルトは`${HOME}/composer`） |
| login_node | Open OnDemandのWebターミナルを起動した際のログイン先 |
| ssh_wrapper | SSHを用いて他のノードのジョブスケジューラを用いる場合のコマンド |
| bin | ジョブスケジューラのコマンドのパス |
| bin_overrides | ジョブスケジューラの各コマンドのパス |
| sge_root | Grid Engineのルート用ディレクトリ（SGE_ROOT） |
| footer | フッタに記載する文字 |
| thumbnail_width | ホームページの各アプリケーションのサムネイルの横幅 |
| navbar_color | ナビゲーションバーの色 |
| dropdown_color | ドロップダウンメニューの色 |
| footer_color | フッタの色 |
| category_color | ホームページのカテゴリの背景色 |
| description_color | アプリケーションページのアプリケーション説明の背景色 |
| form_color | アプリケーションページのテキストエリアの背景色 |

### bin_overridesの設定（オプション）
ジョブスケジューラが`slurm`の場合は、`sbatch`、`scontrol`、`scancel`、`sacct`を設定します。

```
bin_overrides:
  sbatch:   "/usr/local/bin/sbatch"
  scontrol: "/usr/local/bin/scontrol"
  scancel:  "/usr/local/bin/scancel"
  sacct:    "/usr/local/bin/sacct"
```

ジョブスケジューラが`pbspro`の場合は、`qsub`、`qstat`、`qdel`を設定します。

```
bin_overrides:
  qsub:   "/usr/local/bin/qsub"
  qstat: "/usr/local/bin/qstat"
  qdel:  "/usr/local/bin/qdel"
```

ジョブスケジューラが`sge`の場合は、`qsub`、`qstat`、`qdel`、`qacct`を設定します。

```
bin_overrides:
  qsub:   "/usr/local/bin/qsub"
  qstat: "/usr/local/bin/qstat"
  qdel:  "/usr/local/bin/qdel"
  qacct: "/usr/local/bin/qacct"
```

ジョブスケジューラが`fujitsu_tcs`の場合は、`pjsub`、`pjstat`、`pjdel`を設定します。

```
bin_overrides:
  pjsub:  "/usr/local/bin/pjsub"
  pjstat: "/usr/local/bin/pjstat"
  pjdel:  "/usr/local/bin/pjdel"
```

### clusterの設定（オプション）

複数のジョブスケジューラを用いる場合に設定します。`name`と`scheduler`は必須で、それぞれクラスタの名前とスケジューラを設定します。また、他のスケジューラに関する設定（`bin`、`bin_overrides`、`sge_root`）も可能です。注意点として、`cluster`を設定する場合は、`cluster`の外部で`scheduler`、`bin`、`bin_overrides`、`sge_root`を設定することはできません。

```
cluster:
  - name: "fugaku"
    scheduler: "fujitsu_tcs"
  - name: "prepost"
    scheduler: "slurm"
    bin_overrides:
      sbatch:   "/usr/local/bin/sbatch"
```

## 管理者によるOpen OnDemandへの登録
Open Composerを`/var/www/ood/apps/sys/`に保存すると、Open OnDemandのホームページにOpen Composerのアイコンが表示されます。Open Composerのアイコンが表示されない場合は、Open OnDemand用の設定ファイル`./manifest.yml`を確認してください。

Open Composer上のアプリケーションをOpen OnDemandのホームページに表示することもできます。例えば、`./sample_apps/Slurm/`というアプリケーションを表示させたい場合は、同名のディレクトリをOpen OnDemandのアプリケーションディレクトリに作成します（`# mkdir /var/www/ood/apps/sys/Slurm`）。そして、そのディレクトリ内に下記のようなOpen OnDemand用の設定ファイル`manifest.yml`を作成します。

```
# cat /var/www/ood/apps/sys/Slurm/manifest.yml
---
name: Slurm
url: https://example.net/pun/sys/OpenComposer/Slurm
```

## 一般ユーザによるOpen OnDemandへの登録
一般ユーザ権限でOpen Composerをインストールすることもできます。ただし、事前に管理者権限でOpen OnDemandの[App Development](https://osc.github.io/ood-documentation/latest/how-tos/app-development/enabling-development-mode.html)の機能を有効化する必要があります。

ナビゲーションバーの「</> Develop」の「My Sandbox Apps (Development)」を選択します（Webブラウザのウィンドウサイズが小さい場合は、「</> Develop」ではなく「</>」と表示されますので注意ください）。

<img src="img/navbar.png" width="400" alt="Navbar">

「New App」をクリックします。

<img src="img/newapp.png" width="400" alt="New App">

「Clone Existing App」をクリックします。

<img src="img/clone.png" width="400" alt="Clone an existing app">

「Directory name」に任意の名前（ここではOpenComposer）、「Git remote」に「[https://github.com/RIKEN-RCCS/OpenComposer.git](https://github.com/RIKEN-RCCS/OpenComposer.git)」を記入し、「Submit」をクリックします。

<img src="img/new_repo.png" width="800" alt="New repository">

「Launch Open Composer」をクリックします。

<img src="img/bundle.png" width="800" alt="Bundle Install">
