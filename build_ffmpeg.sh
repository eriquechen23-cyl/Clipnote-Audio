#!/usr/bin/env bash
set -euxo pipefail

# 1) 指定 NDK（注意：用 $HOME，不要把 ~ 放進引號）
NDK_PATH="$HOME/Android/Sdk/ndk/29.0.13846066"
TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64"

# 2) 目標與輸出
API=21                           # arm64 常見 minSdk
PREFIX="$PWD/build/android/arm64-v8a"

# 3) 編譯器與工具（用 NDK wrapper，最穩）
CC_BIN="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang"
CXX_BIN="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang++"
AR_BIN="$TOOLCHAIN/bin/llvm-ar"
NM_BIN="$TOOLCHAIN/bin/llvm-nm"
STRIP_BIN="$TOOLCHAIN/bin/llvm-strip"

# 4) 環境檢查
"$CC_BIN" --version
test -d "$TOOLCHAIN/sysroot"

# 5) 組譯前置（若有 .s 需經過 CPP，可保險帶上）
export ASFLAGS="-x assembler-with-cpp"

# 6) configure（只出 .so；關掉 response files 以避免 @file 問題）
./configure \
  --prefix="$PREFIX" \
  --target-os=android \
  --arch=aarch64 \
  --enable-cross-compile \
  --sysroot="$TOOLCHAIN/sysroot" \
  --cc="$CC_BIN" --cxx="$CXX_BIN" \
  --ar="$AR_BIN" --nm="$NM_BIN" --strip="$STRIP_BIN" \
  --enable-shared --disable-static \
  --disable-programs --disable-doc \
  --disable-response-files \
  --extra-cflags="-I$PWD/compat/stdbit"

# 7) build & install
make -j"$(nproc)"
make install

echo "✅ 完成：$PREFIX/lib"

