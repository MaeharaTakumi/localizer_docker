# localizer_rl_docker
NDT + EKF（ekf_localizer / robot_localization）Localizer using Velodyne VLP-16 + WHILL odometry for wheelchair group

[localizer_ekf_docker](https://github.com/MaeharaTakumi/localizer_ekf_docker) をベースに、EKF を
[robot_localization](https://github.com/cra-ros-pkg/robot_localization) に切り替えて試せるようにしたもの

|リポジトリ|ブランチ|パッケージ|
|:--|:--|:--|
|[MaeharaTakumi/lidarslam_ros2](https://github.com/MaeharaTakumi/lidarslam_ros2)|humble|`lidarslam` `scanmatcher` `graph_based_slam` `lidarslam_msgs` `ndt_omp_ros2`(submodule)|
|[MaeharaTakumi/lidar_localization](https://github.com/MaeharaTakumi/lidar_localization)|humble|`pcl_localization_ros2`(NDT)|
|[MaeharaTakumi/whill_odometry](https://github.com/MaeharaTakumi/whill_odometry)|humble|`whill_odometry`|
|[MaeharaTakumi/ekf_localizer](https://github.com/MaeharaTakumi/ekf_localizer)|humble|`ekf_localizer`(EKF)|
|[MaeharaTakumi/localization_bringup](https://github.com/MaeharaTakumi/localization_bringup)|robot_localization|`localization_bringup`(NDT・EKF・whill_odometry を環境ごとの設定で起動)|
|[MaeharaTakumi/localization_tools](https://github.com/MaeharaTakumi/localization_tools)|main|ROS のパッケージではない。`/root/localization_tools`(検証・調整・描画・Gazebo と実機のテスト走行と録画)|

### ベース(localizer_ekf_docker)からの主な変更点
* `ros-humble-robot-localization` を入れた。`localization_bringup` の `robot_localization` ブランチで
  `estimator:=robot_localization` を付けると、`ekf_localizer` の代わりに robot_localization(2 段 EKF)で推定する
* `localization_bringup` だけ別のブランチを取得できる build-arg `BRINGUP_BRANCH` を追加(既定は開発中の `robot_localization`)
* [localization_tools](https://github.com/MaeharaTakumi/localization_tools) を `/root/localization_tools` に入れた(build-arg `TOOLS_BRANCH`、既定 `main`)
* 地図・録画・図の置き場所 `/root/ros2_ws/map`・`/root/ros2_ws/bags/{gazebo,real}`・`/root/ros2_ws/fig` を作る(`COLCON_IGNORE` 入り。下記)。
  `savemap` の保存先と `localization` の地図選択の初期フォルダも `/root/ros2_ws/map`
* `.bashrc` の通信設定の既定を Gazebo 用にした
* イメージ名 `localizer_rl:latest` / コンテナ名 `test_maehara`(localizer_ekf・whill_localizer と並べて使える。
  同時に自己位置推定を動かすと同じ ROS_DOMAIN_ID でぶつかるので、動かすのは 1 つだけにする)

## 2026/02/20現在で確認している不具合
### 最新GPU搭載(NVIDIA GeForce RTX 50xx 等)のPCで自己位置推定が不安定

原因: コンテナのOS(Ubuntu22.04)が最新GPUを識別不能なため

対策: 本Dockerコンテナを`run`したあと，**コンテナ内の**`.bashrc`に以下を追記:
```
export MESA_LOADER_DRIVER_OVERRIDE=zink
```
**動作確認済みGPU**

RTX 5070 Ti Laptop

## Installation
Docker 23.0 以降(BuildKit が既定で有効)が必要

### ビルドとコンテナ作成(Dockerfileがある階層で実行)
```
docker compose up -d --build
```
コンテナに入る:
```
docker exec -it test_maehara bash
```

### (docker compose を使わない場合)
```
docker build -t localizer_rl:latest .
```
```
docker run -itd --ipc=host --gpus=all --env="NVIDIA_DRIVER_CAPABILITIES=all" --net host --privileged -e DISPLAY=unix${DISPLAY} -e NVIDIA_VISIBLE_DEVICES=0 -v /tmp/.X11-unix:/tmp/.X11-unix --name test_maehara localizer_rl:latest
```

## Host側の.bashrc に以下を追記:
```
xhost +local:
```

## リポジトリを更新したとき
もう一度ビルドすると、各リポジトリのブランチ(`humble`、`localization_bringup` は `robot_localization`、`localization_tools` は `main`)の最新コミットが取り込まれる
(コミットが変わっていなければキャッシュが使われ、すぐ終わる)
```
docker compose up -d --build
```

別のユーザー・ブランチから取得したい場合:
```
docker build -t localizer_rl:latest --build-arg REPO_OWNER=<GitHubユーザー名> --build-arg REPO_BRANCH=<ブランチ名> .
```
`localization_bringup` だけ別のブランチにする場合(例: `humble` に戻す):
```
docker compose build --build-arg BRINGUP_BRANCH=humble && docker compose up -d
```

## 地図・録画・図(コンテナを作り直す前に退避する)
地図は `/root/ros2_ws/map`、録画は `/root/ros2_ws/bags/gazebo`(Gazebo)・`/root/ros2_ws/bags/real`(実機)、図は `/root/ros2_ws/fig`
(`localization_tools` の `eval/bag_paths.py`)。**コンテナの中なので、`docker compose up --build` などでコンテナを作り直すと消える**
(`docker stop`・`start` では残る。地図はイメージに入っていない)。作り直す前にホストへ写し、作り直したら戻す。
2026-10-14 にコンテナ名を `localizer_rl` から `test_maehara` に `docker rename` で変えたので、そのとき動いていたコンテナは
次の `docker compose up -d` で作り直される(compose の設定と名前が違うため):
```
docker cp test_maehara:/root/ros2_ws/map <ホストの退避先>/
docker cp test_maehara:/root/ros2_ws/bags <ホストの退避先>/
docker cp test_maehara:/root/ros2_ws/fig <ホストの退避先>/
```

# 実行可能コマンド一覧
|コマンド|実行内容|備考|
|:------|:-----|:---|
|`lidarslam`|NDT-SLAMを実行||
|`savemap`|MAP(.pcd)を保存|`lidarslam`実行中に別terminalで実行する|
|`localization`|MAPを選んで自己位置推定を実行|whill_odometry・NDT・EKF を起動する(実機用)。車椅子は `WHILL=red localization` のように色を付ける(既定は `real.yaml` の `blue`)|
|`odometry`|`whill_odometry` のみを起動||
|`slam_params`|SLAM parameterを確認/編集*|保存後の次回起動時に反映される|
|`lclz_params`|Matching(NDT) parameterを確認/編集*|保存後の次回起動時に反映される|
|`ekf_params`|EKF parameterを確認/編集*|保存後の次回起動時に反映される|
|`odom_params`|Odometry parameterを確認/編集*|保存後の次回起動時に反映される|
|`reload`|terminalの再読込||

*: vscodeにAttachして実行

## トピックの流れ(localization 実行時)
```
whill_node (WHILL側) ── /Drp5_whill_<色>/whill_node/motor_speed_ts ──▶ whill_odometry ── /wheelchair/odom ──▶ ekf_localizer ──▶ /ekf_pose, TF(map→base_link)
VLP-16 ── /velodyne_points ──▶ cloud_stamp_corrector ── /localization/points ──▶ pcl_localization ── /ndt_pose ──▶ ekf_localizer
```
車椅子の色(`blue`・`red`・`white`)は launch の `whill:=<色>`(既定は `real.yaml` の `blue`)。
トピック名・フレーム名などの環境ごとの設定は `localization_bringup` の `param/env/real.yaml` で変更する
(詳細は [localization_bringup](https://github.com/MaeharaTakumi/localization_bringup))

## Gazebo で使う場合
`.bashrc` の通信設定は既定で Gazebo 用(localhost のみ。Gazebo コンテナ・MATLAB と同じ `fastdds_localhost.xml`)。
```
ros2 launch localization_bringup localization.launch.py env:=gazebo map_path:=<PCDファイルのパス>
```
robot_localization で推定する場合(`localization_bringup` の `robot_localization` ブランチが必要):
```
ros2 launch localization_bringup localization.launch.py env:=gazebo estimator:=robot_localization map_path:=<PCDファイルのパス>
```

## 実機で使う場合
コンテナ内の `~/.bashrc` の通信設定を切り替える(Gazebo 用の行をコメントアウトし、実機用の行のコメントを外す)。
新しい terminal で `localization` を実行する

# Paramter変更時の参照箇所
`slam_params`/`lclz_params`/`ekf_params`/`odom_params`が使えない場合に参照
### SLAM
`~/ros2_ws/src/lidarslam_ros2/lidarslam/param/lidarslam.yaml`

https://github.com/MaeharaTakumi/lidarslam_ros2#params

### Matching(NDT)
`~/ros2_ws/src/lidar_localization/param/localization.yaml`

https://github.com/MaeharaTakumi/lidar_localization#params

### EKF
`~/ros2_ws/src/ekf_localizer/param/ekf.yaml`

### Odometry
`~/ros2_ws/src/whill_odometry/config/odometry.yaml`

### 環境ごとの設定(トピック名・取付位置・パラメータの上書き)
`~/ros2_ws/src/localization_bringup/param/env/real.yaml`

# コンテナ内から git push する場合
`~/ros2_ws/src` の各リポジトリは、pull は HTTPS(鍵不要)、push は SSH(`git@github.com:MaeharaTakumi/...`)に設定してある。
push するにはコンテナ内に GitHub 用の SSH 鍵が必要(例: ホストの鍵をコピー)
```
docker exec test_maehara mkdir -p /root/.ssh
```
```
docker cp ~/.ssh/id_ed25519 test_maehara:/root/.ssh/id_ed25519
```


# 使用時の注意
* 初めてコンテナをAttachする場合、ネット環境に接続する
