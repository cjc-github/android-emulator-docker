# Android Emulator Docker 手动构建与操作手册

这份手册从源码构建一个本地 Docker 镜像，并运行其中的无界面 Android 模拟器。整个流程不使用、不生成，也不依赖任何 tar 镜像包。

默认配置：

- 基础系统：Ubuntu 22.04 x86-64
- Android：Android 12 / API 31
- 系统镜像：Google APIs x86_64
- 虚拟设备：Pixel 5
- 图形：SwiftShader 软件渲染
- CPU 加速：宿主机 KVM
- 操作方式：容器内 ADB

## 1. 理解最终产物

构建完成后，Docker 本地镜像列表中会出现：

```text
android-emulator:api31
```

镜像保存在 Docker Engine 自己的存储目录中。不要执行 `docker save`，也不需要创建 `.tar` 文件。

## 2. 检查宿主机

### 2.1 支持范围和资源要求

本项目依赖 Linux KVM，不是纯软件模拟器镜像。推荐环境：

- x86-64 Linux 物理机，或已开启嵌套虚拟化的 x86-64 Linux 虚拟机
- Docker Engine 24.0 或更高版本，使用 rootful 模式
- Intel VT-x（`vmx`）或 AMD-V（`svm`）
- `/dev/kvm` 可传入容器
- 至少 4 核 CPU、8 GB 内存、15 GB 可用磁盘

Docker Desktop for macOS/Windows 无法按本手册直接传入 Linux 宿主机的 `/dev/kvm`。ARM64 主机也不能直接运行当前的 `x86_64` Android 系统镜像。云主机或虚拟机还需要云平台/上层虚拟机开启 nested virtualization。

本项目不使用 libvirt，因此不要求安装 `libvirt-daemon-system`、`virt-manager` 或运行 libvirtd。

### 2.2 安装 Docker Engine（Ubuntu）

如果宿主机还没有 Docker，建议使用 Docker 官方 APT 仓库：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update
sudo apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin
sudo systemctl enable --now docker
```

本项目实际只要求 Docker CLI 和 Docker Engine；Buildx 与 Compose 插件不是当前脚本的硬依赖，但通常建议随 Docker 一起安装。

允许当前用户执行 Docker 命令：

```bash
sudo usermod -aG docker "$USER"
```

`docker` 组具有接近 root 的宿主机权限。添加后需要注销并重新登录，或者重新建立登录会话。

确认 Docker 可用：

```bash
docker version
docker info
```

不要使用 rootless Docker 运行本项目；rootless 模式不能可靠地把 `/dev/kvm` 交给容器。

### 2.3 安装和启用 KVM（Ubuntu/Debian）

安装本项目需要的 KVM 工具：

```bash
sudo apt-get update
sudo apt-get install -y qemu-kvm cpu-checker
```

检查 BIOS/UEFI 或上层虚拟机是否暴露硬件虚拟化：

```bash
grep -E -c '(vmx|svm)' /proc/cpuinfo
sudo kvm-ok
```

第一条命令输出应大于 `0`，`kvm-ok` 应报告可以使用 KVM acceleration。如果 CPU 支持但模块未加载，可执行：

```bash
sudo modprobe kvm

# Intel 主机二选一：
sudo modprobe kvm_intel

# AMD 主机二选一：
sudo modprobe kvm_amd
```

检查模块和设备：

```bash
lsmod | grep '^kvm'
ls -l /dev/kvm
```

需要直接访问 KVM 时，将当前用户加入 `kvm` 组：

```bash
sudo usermod -aG kvm "$USER"
```

重新登录后，用项目脚本一次性检查所有宿主机条件：

```bash
./scripts/check-host.sh
```

该脚本检查 Linux、x86-64、Docker Engine、rootless 模式、CPU `vmx`/`svm` 标志以及 `/dev/kvm`，不会修改宿主机。

### 2.4 手动快速检查

确认宿主机是 x86-64 Linux：

```bash
uname -m
```

预期输出：

```text
x86_64
```

再次确认 Docker 可用：

```bash
docker version
docker info
```

确认 CPU 支持虚拟化：

```bash
grep -E -c '(vmx|svm)' /proc/cpuinfo
```

输出大于 `0` 表示 CPU 暴露了 Intel VT-x 或 AMD-V。

确认 KVM 设备存在：

```bash
ls -l /dev/kvm
```

如果 `/dev/kvm` 不存在，请返回上一节检查 BIOS/UEFI、嵌套虚拟化和 KVM 模块。

## 3. 查看项目源码

进入项目目录：

```bash
cd /home/test/docker/android-emulator-docker
```

源码结构：

```text
android-emulator-docker/
├── .dockerignore
├── Dockerfile
├── README.md
├── entrypoint.sh
├── docs/
│   └── MANUAL.md
└── scripts/
    ├── build-image.sh
    ├── check-host.sh
    ├── remove-emulator.sh
    ├── run-emulator.sh
    ├── setup.sh
    └── verify-emulator.sh
```

建议先阅读 Dockerfile：

```bash
less Dockerfile
```

Dockerfile 依次完成以下工作：

1. 使用 Ubuntu 22.04 amd64 基础镜像。
2. 安装 Java 17 和 Emulator 所需的 Linux 动态库。
3. 下载固定版本的 Android Command-line Tools。
4. 接受 Android SDK License。
5. 安装 `platform-tools`、`emulator` 和 API 31 系统镜像。
6. 创建名为 `docker-emulator` 的 Pixel 5 AVD。
7. 复制容器入口脚本并配置健康检查。

查看入口脚本：

```bash
less entrypoint.sh
```

入口脚本负责：

1. 检查 `/dev/kvm`。
2. 启动 headless Emulator。
3. 等待 ADB 连接。
4. 等待 `sys.boot_completed=1`。
5. 关闭 Android 动画以提高自动化执行速度。
6. 收到 Docker 停止信号时正常关闭 Emulator。

## 4. 手动构建镜像

先检查脚本语法：

```bash
bash -n entrypoint.sh
```

执行构建：

```bash
docker build \
  --network=host \
  --build-arg EMULATOR_CHANNEL=0 \
  --build-arg ANDROID_API_LEVEL=31 \
  --build-arg SYSTEM_IMAGE=google_apis \
  --build-arg AVD_NAME=docker-emulator \
  --build-arg DEVICE_PROFILE=pixel_5 \
  -t android-emulator:api31 \
  .
```

`--network=host` 只影响构建阶段，用于绕过部分 Linux 主机上的 Docker bridge DNS 问题，不会让最终容器自动使用 host 网络。

第一次构建会从 Ubuntu 和 Google 下载数 GB 内容。完成后检查镜像：

```bash
docker image ls android-emulator:api31
docker image inspect android-emulator:api31
```

确认镜像中没有暴露端口：

```bash
docker image inspect \
  --format '{{json .Config.ExposedPorts}}' \
  android-emulator:api31
```

输出应为 `null`。

## 5. 手动启动模拟器

```bash
docker run -d \
  --name android-emulator \
  --device /dev/kvm \
  --shm-size=2g \
  android-emulator:api31
```

参数说明：

- `--device /dev/kvm`：把宿主机 KVM 设备交给容器。
- `--shm-size=2g`：避免 Emulator 图形和共享内存不足。
- 不使用 `-p`：镜像没有对外服务，不暴露 ADB 调试端口。

查看启动日志：

```bash
docker logs -f android-emulator
```

出现下面的内容表示 Android 已完成启动：

```text
Android emulator is ready
```

查看容器健康状态：

```bash
docker inspect \
  --format '{{.State.Status}} / {{.State.Health.Status}}' \
  android-emulator
```

预期输出：

```text
running / healthy
```

## 6. 手动验证 Android

查看 ADB 设备：

```bash
docker exec android-emulator adb devices -l
```

查看 Android 版本：

```bash
docker exec android-emulator \
  adb -s emulator-5554 shell getprop ro.build.version.release
```

查看 API Level：

```bash
docker exec android-emulator \
  adb -s emulator-5554 shell getprop ro.build.version.sdk
```

默认预期为：

```text
12
31
```

进入 Android Shell：

```bash
docker exec -it android-emulator adb -s emulator-5554 shell
```

## 7. 安装和测试 APK

复制 APK 到容器：

```bash
docker cp ./app.apk android-emulator:/tmp/app.apk
```

安装：

```bash
docker exec android-emulator \
  adb -s emulator-5554 install -r /tmp/app.apk
```

列出第三方应用：

```bash
docker exec android-emulator \
  adb -s emulator-5554 shell pm list packages -3
```

截图：

```bash
docker exec android-emulator \
  adb -s emulator-5554 exec-out screencap -p > screenshot.png
```

查看日志：

```bash
docker exec android-emulator adb -s emulator-5554 logcat
```

## 8. 停止和清理容器

正常停止：

```bash
docker stop android-emulator
```

重新启动已有容器：

```bash
docker start android-emulator
```

删除容器但保留镜像：

```bash
docker rm -f android-emulator
```

删除镜像：

```bash
docker image rm android-emulator:api31
```

这些命令都不涉及 tar 文件。

## 9. 使用脚本自动执行

赋予脚本执行权限：

```bash
chmod +x scripts/*.sh
```

检查宿主机依赖：

```bash
./scripts/check-host.sh
```

只构建镜像：

```bash
./scripts/build-image.sh
```

只启动容器：

```bash
./scripts/run-emulator.sh
```

等待并验证 Android：

```bash
./scripts/verify-emulator.sh
```

从构建到验证全部执行：

```bash
./scripts/setup.sh
```

删除测试容器：

```bash
./scripts/remove-emulator.sh
```

`setup.sh` 会依次执行宿主机检查、构建、启动和验证。

## 10. 更换 Android 系统和 Emulator 版本

“Android 模拟器版本”可能指两个不同的版本：

1. Android 系统版本：AVD 内运行 Android 12、Android 15 等，由 API Level 和系统镜像决定。
2. Emulator 引擎版本：宿主 Android SDK 中基于 QEMU 的 `emulator` 程序，例如当前镜像中的 `36.6.11.0`。

`CMDLINE_TOOLS_VERSION` 只控制 `sdkmanager`/`avdmanager` 所在的 Command-line Tools，不是 Android 系统版本，也不是 Emulator 引擎版本。

### 10.1 更换 Android 系统版本（推荐方式）

常见对应关系：

| Android 版本 | API Level |
| --- | ---: |
| Android 12 | 31 |
| Android 12L | 32 |
| Android 13 | 33 |
| Android 14 | 34 |
| Android 15 | 35 |
| Android 16 | 36 |

版本是否能构建，以 Google SDK 仓库中是否存在目标 `x86_64` 系统镜像为准。

例如从默认 API 31 切换到 Android 15 / API 35：

```bash
./scripts/remove-emulator.sh

IMAGE_NAME=android-emulator:api35 \
ANDROID_API_LEVEL=35 \
SYSTEM_IMAGE=google_apis \
DEVICE_PROFILE=pixel_6 \
./scripts/setup.sh
```

必须同时设置 `IMAGE_NAME` 和 `ANDROID_API_LEVEL`：镜像标签不会根据 API 自动变化。旧容器也必须先删除，否则同名容器仍然指向旧镜像；运行脚本会检测并拒绝这种不一致。

也可以分步执行：

```bash
IMAGE_NAME=android-emulator:api35 \
ANDROID_API_LEVEL=35 \
SYSTEM_IMAGE=google_apis \
DEVICE_PROFILE=pixel_6 \
./scripts/build-image.sh

IMAGE_NAME=android-emulator:api35 ./scripts/run-emulator.sh
./scripts/verify-emulator.sh
```

### 10.2 选择系统镜像类型

`SYSTEM_IMAGE` 常见取值如下，但并非每个 API 都提供全部类型：

| 值 | 用途 |
| --- | --- |
| `google_apis` | 包含 Google APIs，适合大多数自动化测试；项目默认值 |
| `google_apis_playstore` | 包含 Google Play 商店；限制更多，且可用 API/架构较少 |
| `default` | 基础 Android 系统镜像，不包含 Google APIs |
| `aosp_atd` | 为自动化测试优化的 AOSP ATD 镜像（仅部分 API） |
| `google_atd` | 包含 Google APIs 的 ATD 镜像（仅部分 API） |

查看某个现有镜像能够查询到的系统镜像包：

```bash
docker run --rm --entrypoint sdkmanager android-emulator:api31 --list \
  | grep 'system-images;android-'
```

例如目标包必须出现类似内容：

```text
system-images;android-35;google_apis;x86_64
```

### 10.3 更换 Emulator 引擎渠道或更新版本

Dockerfile 使用 `sdkmanager "emulator"`。这会安装所选渠道在构建时可用的最新 Emulator 引擎，而不是固定某个旧版本。

渠道参数：

| `EMULATOR_CHANNEL` | 渠道 |
| ---: | --- |
| `0` | Stable（默认） |
| `1` | Beta |
| `2` | Dev |
| `3` | Canary |

更新到当前最新稳定版时要绕过 Docker 缓存：

```bash
BUILD_NO_CACHE=true \
EMULATOR_CHANNEL=0 \
IMAGE_NAME=android-emulator:api31 \
./scripts/build-image.sh
```

尝试 Beta 渠道：

```bash
BUILD_NO_CACHE=true \
EMULATOR_CHANNEL=1 \
IMAGE_NAME=android-emulator:api31-beta \
./scripts/build-image.sh
```

查看实际安装的版本：

```bash
docker run --rm --entrypoint emulator \
  android-emulator:api31 -version

docker run --rm --entrypoint sdkmanager \
  android-emulator:api31 --list_installed
```

`sdkmanager` 的 `emulator` 包路径没有类似 `emulator;36.6.11` 的常规精确版本参数，因此当前项目支持按渠道获取构建时最新版本，不支持直接指定任意历史 Emulator 引擎版本。若必须精确锁定历史引擎，需要改为下载指定 Google Emulator ZIP、校验 SHA-256 并解压到 `${ANDROID_HOME}/emulator`；不要把 `CMDLINE_TOOLS_VERSION` 当作该锁定参数。

### 10.4 更换 Command-line Tools 版本

只有在 `sdkmanager`/`avdmanager` 兼容性需要时才修改：

```bash
CMDLINE_TOOLS_VERSION=11076708 \
BUILD_NO_CACHE=true \
./scripts/build-image.sh
```

该数值必须对应 Google 仓库中真实存在的 `commandlinetools-linux-<版本>_latest.zip`。

## 11. 常见问题

### Docker 构建时域名解析失败

典型错误：

```text
Temporary failure resolving 'archive.ubuntu.com'
```

使用手册中的 `--network=host` 构建。脚本默认已经启用该选项。

### 容器提示 KVM 不可用

检查：

```bash
ls -l /dev/kvm
docker inspect android-emulator --format '{{json .HostConfig.Devices}}'
```

确保启动命令包含 `--device /dev/kvm`。

如果项目运行在虚拟机或云主机内，还要在上层虚拟化平台开启 nested virtualization。仅安装 `qemu-kvm` 不会自动为虚拟机暴露 VT-x/AMD-V。

### `docker` 命令提示 permission denied

检查 Docker 服务和用户组：

```bash
sudo systemctl status docker
id
ls -l /var/run/docker.sock
```

执行 `sudo usermod -aG docker "$USER"` 后必须重新登录。不要通过把 Docker socket 改成全员可写来绕过权限问题。

### 模拟器启动超时

查看日志：

```bash
docker logs android-emulator
```

可把超时提高到 600 秒：

```bash
docker run -d \
  --name android-emulator \
  --device /dev/kvm \
  --shm-size=2g \
  -e BOOT_TIMEOUT=600 \
  android-emulator:api31
```

### 没有图形窗口

这是预期行为。镜像使用 `-no-window`，面向 ADB 调试和自动化测试，不包含桌面、VNC 或浏览器界面。

### APK 无法安装

该模拟器使用 x86_64 系统镜像。APK 应包含 x86_64 原生库，或者完全使用 Java/Kotlin 字节码。只有 ARM 原生库的 APK 不保证可运行。

### 磁盘占用较大

Android 系统镜像本身通常需要数 GB。首次启动时容器还会生成 AVD userdata，因此运行中的容器会额外占用磁盘。不要通过 `docker commit` 把运行态 userdata 打进镜像。
