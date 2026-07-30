# 贡献指南

感谢参与 Android Emulator Docker 项目。提交改动前，请确保变更范围清晰，并且不会把本地凭据、Android 运行状态或大型构建产物加入仓库。

## 分支建议

从最新的 `main` 创建短期分支：

```bash
git switch main
git pull --ff-only
git switch -c docs/update-kvm-guide
```

推荐使用以下前缀：

- `feat/`：新增功能
- `fix/`：修复问题
- `docs/`：文档调整
- `chore/`：工具或仓库维护

## 本地检查

所有提交至少执行 Shell 语法检查：

```bash
bash -n entrypoint.sh scripts/*.sh
```

涉及宿主机或运行脚本时执行：

```bash
./scripts/check-host.sh
./scripts/verify-emulator.sh
```

涉及 Dockerfile、Android API 或 Emulator 渠道时，使用独立标签构建，避免覆盖正在使用的镜像：

```bash
IMAGE_NAME=android-emulator:test ./scripts/build-image.sh
IMAGE_NAME=android-emulator:test \
CONTAINER_NAME=android-emulator-test \
./scripts/run-emulator.sh
CONTAINER_NAME=android-emulator-test ./scripts/verify-emulator.sh
CONTAINER_NAME=android-emulator-test ./scripts/remove-emulator.sh
```

## 提交要求

- 不提交 `.env`、私钥、Token 或其他凭据。
- 不提交 APK、AVD 数据、Docker 导出 tar 包或截图等本地产物。
- Shell 脚本保持 Bash 严格模式，并使用 LF 换行。
- 修改默认参数时同步更新 `README.md` 和 `docs/MANUAL.md`。
- 一个提交尽量只处理一类问题，提交信息使用祈使语气并说明目的。

提交信息示例：

```text
feat: support selecting emulator release channel
fix: reject a container created from an outdated image
docs: document Docker and KVM prerequisites
```

## Pull Request

Pull Request 中请说明：

1. 为什么需要该改动。
2. 改动影响哪些镜像、脚本或宿主机环境。
3. 实际执行过哪些验证命令及结果。
4. 是否存在兼容性变化或需要重新构建镜像。
