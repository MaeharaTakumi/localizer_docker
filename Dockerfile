# syntax=docker/dockerfile:1

# ros2_ws/src に取得するリポジトリ（https://github.com/<REPO_OWNER>/<repo> の <REPO_BRANCH>）
ARG REPO_OWNER=MaeharaTakumi
ARG REPO_BRANCH=humble
# localization_bringup だけ別のブランチにするとき（開発中のブランチを試すなど）に --build-arg BRINGUP_BRANCH=<ブランチ> で変える
ARG BRINGUP_BRANCH=humble
# 検証・調整・描画・テスト走行のツール（ROS のパッケージではないので src の外の /root/ros2_ws/localization_tools に置く。
# リポジトリに COLCON_IGNORE があるので colcon は中を探さない）
ARG TOOLS_BRANCH=main

# ============================================================
# リポジトリ更新検知用ステージ
# BuildKit が各リポジトリのブランチ先端のコミットを毎回確認する。
# コミットが変わったときだけ、下の git clone 以降のキャッシュが破棄される
# （このステージの中身は最終イメージには入らない）
# ============================================================
FROM scratch AS repo_rev
ARG REPO_OWNER
ARG REPO_BRANCH
ARG BRINGUP_BRANCH
ARG TOOLS_BRANCH
ADD https://github.com/${REPO_OWNER}/lidarslam_ros2.git#${REPO_BRANCH} /lidarslam_ros2
ADD https://github.com/${REPO_OWNER}/lidar_localization.git#${REPO_BRANCH} /lidar_localization
ADD https://github.com/${REPO_OWNER}/whill_odometry.git#${REPO_BRANCH} /whill_odometry
ADD https://github.com/${REPO_OWNER}/ekf_localizer.git#${REPO_BRANCH} /ekf_localizer
ADD https://github.com/${REPO_OWNER}/localization_bringup.git#${BRINGUP_BRANCH} /localization_bringup
ADD https://github.com/${REPO_OWNER}/localization_tools.git#${TOOLS_BRANCH} /localization_tools

# ============================================================
# 本体
# ============================================================
FROM ubuntu:22.04

ENV TZ=Asia/Tokyo
ENV DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-c"]

# ---------- ROS 2 Humble（リポジトリ更新時もここはキャッシュを再利用） ----------
RUN apt-get update && \
    apt-get install -y \
    curl \
    git \
    gnupg \
    nano \
    vim \
    openssh-server \
    sudo \
    tzdata \
    udev \
    zenity \
    software-properties-common && \
    ln -sf /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata && \
    add-apt-repository universe && \
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key -o /usr/share/keyrings/ros-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" > /etc/apt/sources.list.d/ros2.list && \
    apt-get update && \
    apt install -y ros-humble-desktop ros-dev-tools && \
    (rosdep init || echo "rosdep already initialized") && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ---------- localization_bringup の Python のノード・localization_tools が使う ----------
RUN apt-get update && \
    apt-get install -y \
    python3-numpy && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ---------- bashrc ----------
RUN cat >> ~/.bashrc <<'EOF'
source /opt/ros/humble/setup.bash
source /root/ros2_ws/install/setup.bash
export ROS_DOMAIN_ID=11

# 通信設定。使う方だけを有効にし、新しい端末を開く（既存の端末には反映されない）
# --- 実機（LiDAR PC と LAN 越しに通信する） ---
# export FASTDDS_BUILTIN_TRANSPORTS=UDPv4
# unset RMW_IMPLEMENTATION FASTRTPS_DEFAULT_PROFILES_FILE ROS_LOCALHOST_ONLY
# --- Gazebo（同じ PC 内だけで通信し、LAN には出ない） ---
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/root/fastdds_localhost.xml
export ROS_LOCALHOST_ONLY=0   # 1 だと共有メモリが追加され、gazebo コンテナと通信できない
unset FASTDDS_BUILTIN_TRANSPORTS
EOF

# ---------- ros2_ws/src の取得 ----------
# fetch は HTTPS（鍵なしで pull できる）、push は SSH（git@github.com:...）にする
ARG REPO_OWNER
ARG REPO_BRANCH
ARG BRINGUP_BRANCH
RUN --mount=type=bind,from=repo_rev,target=/tmp/repo_rev \
    mkdir -p /root/ros2_ws/src && \
    cd /root/ros2_ws/src && \
    for repo in lidarslam_ros2 lidar_localization whill_odometry ekf_localizer localization_bringup; do \
      branch=${REPO_BRANCH}; [ "${repo}" = localization_bringup ] && branch=${BRINGUP_BRANCH}; \
      git clone --recursive -b ${branch} https://github.com/${REPO_OWNER}/${repo}.git && \
      git -C ${repo} remote set-url --push origin git@github.com:${REPO_OWNER}/${repo}.git || exit 1; \
    done

# ---------- 依存パッケージのインストールとビルド ----------
RUN cd /root/ros2_ws && \
    source /opt/ros/humble/setup.bash && \
    apt-get update && \
    rosdep update --rosdistro humble && \
    rosdep install --from-paths src --ignore-src -r -y && \
    colcon build --symlink-install --cmake-args -DCMAKE_BUILD_TYPE=Release && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# ---------- 検証・調整・描画・テスト走行のツール ----------
ARG TOOLS_BRANCH
RUN --mount=type=bind,from=repo_rev,target=/tmp/repo_rev \
    git clone -b ${TOOLS_BRANCH} https://github.com/${REPO_OWNER}/localization_tools.git /root/ros2_ws/localization_tools && \
    git -C /root/ros2_ws/localization_tools remote set-url --push origin git@github.com:${REPO_OWNER}/localization_tools.git

# ---------- 地図・録画・図の置き場所（地図は savemap・localization、録画と図は localization_tools の eval/bag_paths.py） ----------
# ros2_ws の下に置くので、colcon が中を探さないよう COLCON_IGNORE を置く。docker-compose.yml ではホストの data/ を割り当てる
# （作り直しても消えない。割り当てないとコンテナの中に置かれ、作り直すと消える）
RUN mkdir -p /root/ros2_ws/map /root/ros2_ws/bags/gazebo/tune /root/ros2_ws/bags/real/tune /root/ros2_ws/fig && \
    touch /root/ros2_ws/map/COLCON_IGNORE /root/ros2_ws/bags/COLCON_IGNORE /root/ros2_ws/fig/COLCON_IGNORE

COPY src/aliases.txt /root/.bash_aliases
COPY src/fastdds_localhost.xml /root/fastdds_localhost.xml
