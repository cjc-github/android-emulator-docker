# Android Emulator Docker

从源码构建一个无界面的 Android 模拟器 Docker 镜像，不依赖也不生成 tar 包。

默认版本：Ubuntu 22.04、Android 12/API 31、Google APIs x86_64、Pixel 5、KVM 加速。

## 宿主机要求

- x86-64 Linux；物理机或已开启嵌套虚拟化的 Linux 虚拟机
- Docker Engine（推荐 24.0 或更高版本，使用 rootful 模式）
- CPU 已开启 Intel VT-x 或 AMD-V，宿主机存在 `/dev/kvm`
- 建议至少 4 核 CPU、8 GB 内存、15 GB 可用磁盘

Ubuntu/Debian 上的 KVM 工具：

```bash
sudo apt-get update
sudo apt-get install -y qemu-kvm cpu-checker
sudo usermod -aG kvm,docker "$USER"
```

重新登录后检查宿主机：

```bash
./scripts/check-host.sh
```

Docker Engine 的完整安装步骤、KVM 模块检查和虚拟机嵌套虚拟化说明见[完整手册](docs/MANUAL.md)。Docker Desktop for macOS/Windows 不能直接使用本项目的 `/dev/kvm` 启动方式。

## 文档

- [完整手动操作手册](docs/MANUAL.md)
- [贡献指南](CONTRIBUTING.md)
- [Dockerfile](Dockerfile)
- [容器启动入口](entrypoint.sh)

## 手动执行

构建：

```bash
docker build --network=host -t android-emulator:api31 .
```

启动：

```bash
docker run -d \
  --name android-emulator \
  --device /dev/kvm \
  --shm-size=2g \
  android-emulator:api31
```

验证：

```bash
docker logs -f android-emulator
docker exec android-emulator adb devices -l
docker exec android-emulator adb -s emulator-5554 shell getprop ro.build.version.release
```

## 使用脚本

```bash
chmod +x scripts/*.sh
./scripts/setup.sh
```

也可以分别执行：

```bash
./scripts/check-host.sh
./scripts/build-image.sh
./scripts/run-emulator.sh
./scripts/verify-emulator.sh
```

删除测试容器：

```bash
./scripts/remove-emulator.sh
```

脚本直接使用 Docker Engine 完成检查、构建、启动和验证，不会调用 `docker save` 或创建 tar 文件。

## 更换 Android 版本

例如构建 Android 15 / API 35：

```bash
./scripts/remove-emulator.sh

IMAGE_NAME=android-emulator:api35 \
ANDROID_API_LEVEL=35 \
SYSTEM_IMAGE=google_apis \
DEVICE_PROFILE=pixel_6 \
./scripts/setup.sh
```

`IMAGE_NAME` 和 `ANDROID_API_LEVEL` 需要一起修改，否则镜像标签可能与实际 Android 版本不一致。目标 API 还必须存在相应的 `x86_64` 系统镜像。

Android 系统版本与 Emulator 引擎是两件事。Dockerfile 默认从稳定渠道安装构建时最新的 Emulator 引擎。更新稳定版引擎：

```bash
BUILD_NO_CACHE=true EMULATOR_CHANNEL=0 ./scripts/build-image.sh
```

渠道值为 `0=Stable`、`1=Beta`、`2=Dev`、`3=Canary`。查看镜像内实际版本：

```bash
docker run --rm --entrypoint emulator android-emulator:api31 -version
docker run --rm --entrypoint sdkmanager android-emulator:api31 --list_installed
```

更多版本示例、系统镜像类型和精确版本限制见[手册的版本切换章节](docs/MANUAL.md#10-更换-android-系统和-emulator-版本)。
