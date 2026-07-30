FROM --platform=linux/amd64 ubuntu:22.04

LABEL org.opencontainers.image.title="Android Emulator"
LABEL org.opencontainers.image.description="Headless Android Emulator with KVM acceleration"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk

ENV PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator"

ARG CMDLINE_TOOLS_VERSION=11076708
ARG EMULATOR_CHANNEL=0
ARG ANDROID_API_LEVEL=31
ARG SYSTEM_IMAGE=google_apis
ARG AVD_NAME=docker-emulator
ARG DEVICE_PROFILE=pixel_5

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip \
        tzdata \
        openjdk-17-jre-headless \
        procps \
        libasound2 \
        libdbus-1-3 \
        libdrm2 \
        libfontconfig1 \
        libgbm1 \
        libgl1 \
        libnss3 \
        libpulse0 \
        libx11-6 \
        libx11-xcb1 \
        libxcb1 \
        libxcomposite1 \
        libxcursor1 \
        libxdamage1 \
        libxext6 \
        libxfixes3 \
        libxi6 \
        libxkbcommon0 \
        libxkbfile1 \
        libxrandr2 \
        libxrender1 \
        libxshmfence1 \
        libxtst6 \
    && ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime \
    && printf '%s\n' "${TZ}" > /etc/timezone \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p "${ANDROID_HOME}/cmdline-tools/latest" /root/.android \
    && touch /root/.android/repositories.cfg \
    && curl -fsSL --retry 5 \
        "https://dl.google.com/android/repository/commandlinetools-linux-${CMDLINE_TOOLS_VERSION}_latest.zip" \
        -o /tmp/cmdline-tools.zip \
    && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
    && mv /tmp/cmdline-tools/cmdline-tools/* "${ANDROID_HOME}/cmdline-tools/latest/" \
    && rm -rf /tmp/cmdline-tools /tmp/cmdline-tools.zip

RUN yes | sdkmanager --licenses >/dev/null \
    && sdkmanager \
        "platform-tools" \
        "system-images;android-${ANDROID_API_LEVEL};${SYSTEM_IMAGE};x86_64" \
    && sdkmanager --channel="${EMULATOR_CHANNEL}" "emulator" \
    && rm -rf "${ANDROID_HOME}/.temp" /root/.android/cache

RUN echo "no" | avdmanager create avd \
        --force \
        --name "${AVD_NAME}" \
        --package "system-images;android-${ANDROID_API_LEVEL};${SYSTEM_IMAGE};x86_64" \
        --device "${DEVICE_PROFILE}" \
    && printf '%s\n' \
        "hw.cpu.ncore=4" \
        "hw.ramSize=4096" \
        "vm.heapSize=512" \
        "disk.dataPartition.size=4G" \
        "hw.gpu.enabled=yes" \
        "hw.gpu.mode=swiftshader_indirect" \
        "hw.keyboard=yes" \
        "showDeviceFrame=no" \
        >> "/root/.android/avd/${AVD_NAME}.avd/config.ini"

COPY entrypoint.sh /entrypoint.sh

RUN chmod 0755 /entrypoint.sh

ENV AVD_NAME="${AVD_NAME}" \
    EMULATOR_CONSOLE_PORT=5554 \
    BOOT_TIMEOUT=300 \
    REQUIRE_KVM=true

STOPSIGNAL SIGTERM

HEALTHCHECK --interval=15s --timeout=10s --start-period=120s --retries=4 \
    CMD adb -s "emulator-${EMULATOR_CONSOLE_PORT}" shell getprop sys.boot_completed 2>/dev/null | grep -q '^1$'

ENTRYPOINT ["/entrypoint.sh"]
