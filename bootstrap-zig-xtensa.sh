#!/bin/bash

set -e  # Exit on error

# For cross-compilation target
TARGET=$1
MCPU=$2

# Validate that both parameters are provided
if [ -z "$TARGET" ] || [ -z "$MCPU" ]; then
    echo "Error: Both TARGET and MCPU must be provided."
    echo "Usage: $0 <target> <cpu>"
    echo "Example: $0 x86_64-linux-gnu baseline"
    exit 1
fi

# Process target OS for CMake
TARGET_OS_AND_ABI=${TARGET#*-}
TARGET_OS_CMAKE=${TARGET_OS_AND_ABI%-*}

case $TARGET_OS_CMAKE in
    macos)
        TARGET_OS_CMAKE=Darwin;;
    freebsd)
        TARGET_OS_CMAKE=FreeBSD;;
    windows)
        TARGET_OS_CMAKE=Windows;;
    linux)
        TARGET_OS_CMAKE=Linux;;
    native)
        TARGET_OS_CMAKE="";;
esac

ROOT_DIR=$(pwd)
HOST_INSTALL_DIR=$ROOT_DIR/out/host
TARGET_INSTALL_DIR=$ROOT_DIR/out/$TARGET-$MCPU
FINAL_INSTALL_DIR=$ROOT_DIR/out/zig-$TARGET-$MCPU

echo "========================================================="
echo "Building Zig bootstrap with the following configuration:"
echo "Target: $TARGET"
echo "CPU: $MCPU"
echo "Root directory: $ROOT_DIR"
echo "Host install directory: $HOST_INSTALL_DIR"
echo "Target install directory: $TARGET_INSTALL_DIR"
echo "Final install directory: $FINAL_INSTALL_DIR"
echo "========================================================="

# Step 1: Build LLVM (host)
echo "[1/6] Building LLVM (host)..."
mkdir -p $ROOT_DIR/out/build-llvm-host
cd $ROOT_DIR/out/build-llvm-host
cmake $ROOT_DIR/llvm \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX=$HOST_INSTALL_DIR \
    -DCMAKE_PREFIX_PATH=$HOST_INSTALL_DIR \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_LIBPFM=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF \
    -DLLVM_ENABLE_PROJECTS="lld;clang" \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_Z3_SOLVER=OFF \
    -DLLVM_ENABLE_ZSTD=OFF \
    -DLLVM_INCLUDE_UTILS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
    -DLLVM_TOOL_LTO_BUILD=OFF \
    -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
    -DCLANG_BUILD_TOOLS=OFF \
    -DCLANG_INCLUDE_DOCS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
    -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
    -DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa

echo "Building LLVM (host)..."
cmake --build . --target install
echo "LLVM (host) build complete."

# Step 2: Build Zig compiler (host, C)
echo "[2/6] Building Zig compiler (host, C)..."
mkdir -p $ROOT_DIR/out/build-zig-host
cd $ROOT_DIR/out/build-zig-host
cmake $ROOT_DIR/zig \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX=$HOST_INSTALL_DIR \
    -DCMAKE_PREFIX_PATH=$HOST_INSTALL_DIR \
    -DCMAKE_BUILD_TYPE=Release
echo "Building Zig compiler (host, C)..."
cmake --build . --target install
echo "Zig compiler (host) build complete."

# Define ZIG variable for subsequent builds
ZIG=$HOST_INSTALL_DIR/bin/zig

# Step 3: Build zlib (target)
echo "[3/6] Building zlib for $TARGET..."
mkdir -p $ROOT_DIR/out/build-zlib-$TARGET-$MCPU
cd $ROOT_DIR/out/build-zlib-$TARGET-$MCPU
cmake $ROOT_DIR/zlib \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX=$TARGET_INSTALL_DIR \
    -DCMAKE_PREFIX_PATH=$TARGET_INSTALL_DIR \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CROSSCOMPILING=True \
    -DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
    -DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
    -DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
    -DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
    -DCMAKE_RC_COMPILER="$HOST_INSTALL_DIR/bin/llvm-rc" \
    -DCMAKE_AR="$HOST_INSTALL_DIR/bin/llvm-ar" \
    -DCMAKE_RANLIB="$HOST_INSTALL_DIR/bin/llvm-ranlib" \
    -DZLIB_BUILD_TESTING=OFF \
    -DZLIB_BUILD_STATIC=ON \
    -DZLIB_BUILD_SHARED=OFF
echo "Building zlib..."
cmake --build . --target install
echo "zlib build complete."

# Step 4: Build zstd (target)
echo "[4/6] Building zstd for $TARGET..."
mkdir -p $TARGET_INSTALL_DIR/lib
cd $ROOT_DIR/zstd
$ZIG build \
    --prefix $TARGET_INSTALL_DIR \
    -Dtarget=$TARGET \
    -Dcpu=$MCPU \
    -Doptimize=ReleaseFast
echo "zstd build complete."

# Step 5: Build LLVM (target)
echo "[5/6] Building LLVM for $TARGET..."
mkdir -p $ROOT_DIR/out/build-llvm-$TARGET-$MCPU
cd $ROOT_DIR/out/build-llvm-$TARGET-$MCPU
cmake $ROOT_DIR/llvm \
    -G Ninja \
    -DCMAKE_INSTALL_PREFIX="$TARGET_INSTALL_DIR" \
    -DCMAKE_PREFIX_PATH="$TARGET_INSTALL_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CROSSCOMPILING=True \
    -DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
    -DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
    -DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
    -DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
    -DCMAKE_RC_COMPILER="$HOST_INSTALL_DIR/bin/llvm-rc" \
    -DCMAKE_AR="$HOST_INSTALL_DIR/bin/llvm-ar" \
    -DCMAKE_RANLIB="$HOST_INSTALL_DIR/bin/llvm-ranlib" \
    -DLLVM_ENABLE_BACKTRACES=OFF \
    -DLLVM_ENABLE_BINDINGS=OFF \
    -DLLVM_ENABLE_CRASH_OVERRIDES=OFF \
    -DLLVM_ENABLE_LIBEDIT=OFF \
    -DLLVM_ENABLE_LIBPFM=OFF \
    -DLLVM_ENABLE_LIBXML2=OFF \
    -DLLVM_ENABLE_OCAMLDOC=OFF \
    -DLLVM_ENABLE_PLUGINS=OFF \
    -DLLVM_ENABLE_PROJECTS="lld;clang" \
    -DLLVM_ENABLE_TERMINFO=OFF \
    -DLLVM_ENABLE_Z3_SOLVER=OFF \
    -DLLVM_ENABLE_ZLIB=FORCE_ON \
    -DLLVM_ENABLE_ZSTD=FORCE_ON \
    -DLLVM_USE_STATIC_ZSTD=ON \
    -DLLVM_TABLEGEN="$HOST_INSTALL_DIR/bin/llvm-tblgen" \
    -DLLVM_BUILD_UTILS=OFF \
    -DLLVM_BUILD_TOOLS=OFF \
    -DLLVM_BUILD_STATIC=ON \
    -DLLVM_INCLUDE_UTILS=OFF \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_INCLUDE_BENCHMARKS=OFF \
    -DLLVM_INCLUDE_DOCS=OFF \
    -DLLVM_DEFAULT_TARGET_TRIPLE="$TARGET" \
    -DLLVM_TOOL_LLVM_LTO2_BUILD=OFF \
    -DLLVM_TOOL_LLVM_LTO_BUILD=OFF \
    -DLLVM_TOOL_LTO_BUILD=OFF \
    -DLLVM_TOOL_REMARKS_SHLIB_BUILD=OFF \
    -DCLANG_TABLEGEN="$ROOT_DIR/out/build-llvm-host/bin/clang-tblgen" \
    -DCLANG_BUILD_TOOLS=OFF \
    -DCLANG_INCLUDE_DOCS=OFF \
    -DCLANG_INCLUDE_TESTS=OFF \
    -DCLANG_ENABLE_ARCMT=ON \
    -DCLANG_TOOL_CLANG_IMPORT_TEST_BUILD=OFF \
    -DCLANG_TOOL_CLANG_LINKER_WRAPPER_BUILD=OFF \
    -DCLANG_TOOL_C_INDEX_TEST_BUILD=OFF \
    -DCLANG_TOOL_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_C_ARCMT_TEST_BUILD=OFF \
    -DCLANG_TOOL_LIBCLANG_BUILD=OFF \
    -DLLD_BUILD_TOOLS=OFF \
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa \
    -DLIBCLANG_BUILD_STATIC=ON
echo "Building LLVM (target)..."
cmake --build . --target install
echo "LLVM (target) build complete."

# Step 6: Build Zig (final)
echo "[6/6] Building final Zig compiler for $TARGET..."
cd $ROOT_DIR/zig
$ZIG build \
    --prefix $FINAL_INSTALL_DIR \
    --search-prefix "$TARGET_INSTALL_DIR" \
    -Dflat \
    -Dstatic-llvm \
    -Doptimize=ReleaseSafe \
    -Dllvm-has-xtensa \
    -Dtarget="$TARGET" \
    -Dcpu="$MCPU"
echo "Final Zig compiler build complete."

echo "========================================================="
echo "Zig bootstrap build complete!"
echo "Final Zig compiler installed at: $FINAL_INSTALL_DIR"
echo "========================================================="