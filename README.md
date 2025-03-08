# Making Zig Generate Code for Espressif Chips

## Background

If you're not familiar with embedded systems or IoT, here's some context about why this matters.

Espressif is a Chinese semiconductor company known for their ESP32 microcontroller series. Released in 2016, the ESP32 has become widely popular in both hobby and professional IoT projects due to its dual-core processor and built-in Wi-Fi/Bluetooth capabilities.

The main development tools for ESP32 are:
- ESP-IDF: Espressif's official IoT Development Framework
- Arduino core: A framework that lets makers use familiar Arduino libraries

Both frameworks are C/C++-based, which is typical for embedded systems. However, newer languages like Rust and Zig are gaining traction. Espressif already supports Rust through their LLVM fork, making it possible to write ESP32 applications in Rust.

Since Zig also uses LLVM for code generation, it should theoretically be possible to use Zig for ESP32 development as well. This exploration aims to make that possible.

## Zig for ESP32

## Existing Solution: zig-espressif-bootstrap

There's already a working solution available at [github.com/kassane/zig-espressif-bootstrap](https://github.com/kassane/zig-espressif-bootstrap).

This repository is a fork of the official Zig bootstrap repo but with added support for Espressif's Xtensa architecture. It uses Espressif's fork of the LLVM project to build a Zig toolchain capable of targeting ESP32 devices.

While the solution exists, there are some important caveats:

1. Simply including Espressif's LLVM fork is not sufficient to make Zig generate code for Xtensa targets
2. The repository lacks comprehensive documentation on the implementation details
3. Several non-obvious modifications are required to make everything work correctly

If you just need a working Zig compiler with Xtensa support, using the zig-espressif-bootstrap repository directly is your best option. However, if you're interested in understanding how the integration works under the hood, the sections below explain the technical journey.
## Building Zig From Source

### Simplest Way

Normally, you will only need these software to build Zig from source:

- CMake (build system)
- LLVM v19.1.x (for code generation)
- Python 3
- C/C++ compiler (GCC or Clang on macOS or Linux)
- zstd library (compression library, Zig's and LLVM's dependency)
- zlib (compression library, LLVM's dependency)
- And of course the Zig source code.

The build step should be as simple as the following shell script assuming CMake can find those packages.

```sh
cmake -B build -S .
cmake --build build --target install
```

Bootstrapping for different machine architectures and adding experimental LLVM target support (like Xtensa) is much more complex, as detailed in the following sections.

## Bootstrapping for Different Machine Architectures

When building Zig for a different architecture (like adding Xtensa support for ESP32), we need to go through a multi-stage bootstrap process. This is more complex than a standard build and involves:

1. Building LLVM (including backend, LLD, and Clang) with the host compiler 
2. Building a host Zig compiler with that LLVM
3. Using that Zig compiler to cross-compile dependencies (zlib, zstd) for the target architecture
4. Using the cross-compiler to build LLVM again, but targeting the destination architecture
5. Finally building the full Zig toolchain for the target architecture

The [ziglang/zig-bootstrap](https://github.com/ziglang/zig-bootstrap) repository handles this process with its build script. It includes all source dependencies locally (except for CMake and the C/C++ compiler), making the bootstrap process more manageable.

While this process works well for established architectures, adding support for experimental architectures like Xtensa presents additional challenges that aren't immediately obvious, as we'll see in the following sections.

### Journey: Building with Xtensa Support

Building LLVM with Xtensa support requires an additional CMake option to be passed into its CLI.

```sh
-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa
```

Here is the complete command and variables for building LLVM using CMake.

```sh
cmake "$ROOTDIR/llvm" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
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
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa \
  -DCLANG_TOOL_LIBCLANG_BUILD=OFF
```

For LLVM, adding the `-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa` is enough. But it's not enough for Zig as we'll see in a minute.

Then we build Zig using CMake and the previously built LLVM.

```sh
cmake "$ROOTDIR/zig" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_VERSION="$ZIG_VERSION"
cmake --build . --target install
```

This step will produce a Zig toolchain that can be used as a cross-compiler.
We can verify its cross-compiling capability by using its built-in C compiler.

```c
// filename: test.c
int add(int a, int b) {
    return a + b;
}
```

```sh
$ROOT_DIR/out/host/bin/zig cc -S test.c -target xtensa-frestanding-none -O1
```

Above command produces an assembly file and here's an excerpt of that file.

```asm
        .text
        .file   "test.c"
        .global add                             # -- Begin function add
        .p2align        2
        .type   add,@function
add:                                    # @add
.Lfunc_begin0:
# %bb.0:
        #DEBUG_VALUE: add:a <- $a2
        #DEBUG_VALUE: add:b <- $a3
        .file   1 "/root/workspace" "test.c"
        .loc    1 2 12 prologue_end             # test.c:2:12
        entry   a1, 32
        or      a7, a1, a1
        add     a2, a3, a2
.Ltmp0:
        .loc    1 2 3 is_stmt 0                 # test.c:2:3
        retw
```

By default Zig will use the `generic` CPU for Xtensa architecture.
Attempting to use `esp32` as the CPU target will produce the following error:

```sh
$ROOT_DIR/out/host/bin/zig cc -S test.c -target xtensa-frestanding-none -O1 -mcpu=esp32
```

```
info: available CPUs for architecture 'xtensa':
 generic

error: unknown CPU: 'esp32'
```
Interestingly, compiling the same code using Clang and LLVM built with Xtensa target enabled will successfully produce assembly code.

```sh
# Build clang out of curiosity
cmake -B build -S llvm \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_ENABLE_PROJECTS="lld;clang" \
    -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa

cmake --build build
```

```sh
./build/bin/clang -S test.c -O1 -target xtensa-freestanding-none -mcpu=esp32
```

```asm
        .text
        .file   "test.c"
        .global add                             # -- Begin function add
        .p2align        2
        .type   add,@function
add:                                    # @add
# %bb.0:
        entry   a1, 32
        add.n   a2, a3, a2
        retw.n
.Lfunc_end0:
        .size   add, .Lfunc_end0-add
                                        # -- End function
        .ident  "clang version 19.1.2 (git@github.com:espressif/llvm-project.git a8a8fecac7a7aa6502410a3a09674bbd688f5903)"
        .section        ".note.GNU-stack","",@progbits
        .addrsig
```

This issue is related with how Zig implements the code generation for specific target such as Xtensa for both C and Zig code compilation.

Then we used the Zig cross compiler to build the zstd and zlib as static libraries for re-building LLVM later on.

```sh
# Now we have Zig as a cross compiler.
ZIG="$ROOTDIR/out/host/bin/zig"

# First cross compile zlib for the target, as we need the LLVM linked into
# the final zig binary to have zlib support enabled.
mkdir -p "$ROOTDIR/out/build-zlib-$TARGET-$MCPU"
cd "$ROOTDIR/out/build-zlib-$TARGET-$MCPU"
cmake "$ROOTDIR/zlib" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/$TARGET-$MCPU" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/$TARGET-$MCPU" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CROSSCOMPILING=True \
  -DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
  -DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_RC_COMPILER="$ROOTDIR/out/host/bin/llvm-rc" \
  -DCMAKE_AR="$ROOTDIR/out/host/bin/llvm-ar" \
  -DCMAKE_RANLIB="$ROOTDIR/out/host/bin/llvm-ranlib"
cmake --build . --target install


# Same deal for zstd.
# The build system for zstd is whack so I just put all the files here.
mkdir -p "$ROOTDIR/out/$TARGET-$MCPU/lib"
cp "$ROOTDIR/zstd/lib/zstd.h" "$ROOTDIR/out/$TARGET-$MCPU/include/zstd.h"
cd "$ROOTDIR/out/$TARGET-$MCPU/lib"
$ZIG build-lib \
  --name zstd \
  -target $TARGET \
  -mcpu=$MCPU \
  -fstrip -OReleaseFast \
  -lc \
  "$ROOTDIR/zstd/lib/decompress/zstd_ddict.c" \
  "$ROOTDIR/zstd/lib/decompress/zstd_decompress.c" \
  "$ROOTDIR/zstd/lib/decompress/huf_decompress.c" \
  "$ROOTDIR/zstd/lib/decompress/huf_decompress_amd64.S" \
  "$ROOTDIR/zstd/lib/decompress/zstd_decompress_block.c" \
  "$ROOTDIR/zstd/lib/compress/zstdmt_compress.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_opt.c" \
  "$ROOTDIR/zstd/lib/compress/hist.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_ldm.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_fast.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress_literals.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_double_fast.c" \
  "$ROOTDIR/zstd/lib/compress/huf_compress.c" \
  "$ROOTDIR/zstd/lib/compress/fse_compress.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_lazy.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress_sequences.c" \
  "$ROOTDIR/zstd/lib/compress/zstd_compress_superblock.c" \
  "$ROOTDIR/zstd/lib/deprecated/zbuff_compress.c" \
  "$ROOTDIR/zstd/lib/deprecated/zbuff_decompress.c" \
  "$ROOTDIR/zstd/lib/deprecated/zbuff_common.c" \
  "$ROOTDIR/zstd/lib/common/entropy_common.c" \
  "$ROOTDIR/zstd/lib/common/pool.c" \
  "$ROOTDIR/zstd/lib/common/threading.c" \
  "$ROOTDIR/zstd/lib/common/zstd_common.c" \
  "$ROOTDIR/zstd/lib/common/xxhash.c" \
  "$ROOTDIR/zstd/lib/common/debug.c" \
  "$ROOTDIR/zstd/lib/common/fse_decompress.c" \
  "$ROOTDIR/zstd/lib/common/error_private.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/zdict.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/divsufsort.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/fastcover.c" \
  "$ROOTDIR/zstd/lib/dictBuilder/cover.c"
```

Then we re-build LLVM for the target architecture using the Zig cross compiler.
We'll need this LLVM as we build the Zig toolchain for the target architecture later on.

```sh
mkdir -p "$ROOTDIR/out/build-llvm-$TARGET-$MCPU"
cd "$ROOTDIR/out/build-llvm-$TARGET-$MCPU"
cmake "$ROOTDIR/llvm" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/$TARGET-$MCPU" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/$TARGET-$MCPU" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CROSSCOMPILING=True \
  -DCMAKE_SYSTEM_NAME="$TARGET_OS_CMAKE" \
  -DCMAKE_C_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_CXX_COMPILER="$ZIG;c++;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_ASM_COMPILER="$ZIG;cc;-fno-sanitize=all;-s;-target;$TARGET;-mcpu=$MCPU" \
  -DCMAKE_RC_COMPILER="$ROOTDIR/out/host/bin/llvm-rc" \
  -DCMAKE_AR="$ROOTDIR/out/host/bin/llvm-ar" \
  -DCMAKE_RANLIB="$ROOTDIR/out/host/bin/llvm-ranlib" \
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
  -DLLVM_TABLEGEN="$ROOTDIR/out/host/bin/llvm-tblgen" \
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
  -DCLANG_TABLEGEN="$ROOTDIR/out/build-llvm-host/bin/clang-tblgen" \
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
  -DLIBCLANG_BUILD_STATIC=ON \
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa \
  -DLLD_BUILD_TOOLS=OFF
cmake --build . --target install
```

Then we build the Zig toolchain for the target architecture using Zig cross compiler.

```sh
$ZIG build \
  --prefix "$ROOTDIR/out/zig-$TARGET-$MCPU" \
  --search-prefix "$ROOTDIR/out/$TARGET-$MCPU" \
  -Dflat \
  -Dllvm-has-xtensa \
  -Dstatic-llvm \
  -Doptimize=ReleaseSafe \
  -Dtarget="$TARGET" \
  -Dcpu="$MCPU" \
  -Dversion-string="$ZIG_VERSION"
```

This build process uses Zig Build System as opposed to the cross compiler using CMake.
The `-Dflat` argument will change the structure of the built toolchain to the following structure:

```
zig-$TARGET-$MCPU
├── LICENSE
├── README.md
├── doc
│   └── langref.html
├── lib
└── zig
```

We used the `ReleaseSafe` build mode to include runtime safety checks in the produced Zig toolchain.

Then we enable the Xtensa target in Zig by providing the `-Dllvm-has-xtensa` argument.

#### Missing LLVM Xtensa Libraries in Zig

The build process failed at the linking step with the following missing symbols:
```
error: undefined symbol: _LLVMInitializeXtensaAsmParser
    note: referenced by out/aarch64-macos-apple_m3/lib/liblldELF.a(Driver.cpp.o):__ZN4llvm23InitializeAllAsmParsersEv
    note: referenced by zig/.zig-cache/o/096f4ec3665323bac559ccb907465c05/zig.o:_codegen.llvm.initializeLLVMTarget
error: undefined symbol: _LLVMInitializeXtensaAsmPrinter
    note: referenced by out/aarch64-macos-apple_m3/lib/liblldELF.a(Driver.cpp.o):__ZN4llvm24InitializeAllAsmPrintersEv
error: undefined symbol: _LLVMInitializeXtensaTarget
    note: referenced by out/aarch64-macos-apple_m3/lib/liblldELF.a(Driver.cpp.o):__ZN4llvm20InitializeAllTargetsEv
    note: referenced by zig/.zig-cache/o/096f4ec3665323bac559ccb907465c05/zig.o:_codegen.llvm.initializeLLVMTarget
error: undefined symbol: _LLVMInitializeXtensaTargetInfo
    note: referenced by out/aarch64-macos-apple_m3/lib/liblldELF.a(Driver.cpp.o):__ZN4llvm24InitializeAllTargetInfosEv
    note: referenced by zig/.zig-cache/o/096f4ec3665323bac559ccb907465c05/zig.o:_codegen.llvm.initializeLLVMTarget
error: undefined symbol: _LLVMInitializeXtensaTargetMC
    note: referenced by out/aarch64-macos-apple_m3/lib/liblldELF.a(Driver.cpp.o):__ZN4llvm22InitializeAllTargetMCsEv
    note: referenced by zig/.zig-cache/o/096f4ec3665323bac559ccb907465c05/zig.o:_codegen.llvm.initializeLLVMTarget
```

Here's the command that fails at the linker step:

```
out/host/bin/zig build-exe --stack 48234496 -cflags -std=c++17 -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -D_GNU_SOURCE -fno-exceptions -fno-rtti -fno-stack-protector -fvisibility-inlines-hidden -Wno-type-limits -Wno-missing-braces -Wno-comment -DNDEBUG=1 -- zig/src/zig_llvm.cpp zig/src/zig_clang.cpp zig/src/zig_llvm-ar.cpp zig/src/zig_clang_driver.cpp zig/src/zig_clang_cc1_main.cpp zig/src/zig_clang_cc1as_main.cpp -lclangFrontendTool -lclangCodeGen -lclangFrontend -lclangDriver -lclangSerialization -lclangSema -lclangStaticAnalyzerFrontend -lclangStaticAnalyzerCheckers -lclangStaticAnalyzerCore -lclangAnalysis -lclangASTMatchers -lclangAST -lclangParse -lclangAPINotes -lclangBasic -lclangEdit -lclangLex -lclangARCMigrate -lclangRewriteFrontend -lclangRewrite -lclangCrossTU -lclangIndex -lclangToolingCore -lclangExtractAPI -lclangSupport -lclangInstallAPI -llldMinGW -llldELF -llldCOFF -llldWasm -llldMachO -llldCommon -lLLVMWindowsManifest -lLLVMXRay -lLLVMLibDriver -lLLVMDlltoolDriver -lLLVMTextAPIBinaryReader -lLLVMCoverage -lLLVMLineEditor -lLLVMSandboxIR -lLLVMXCoreDisassembler -lLLVMXCoreCodeGen -lLLVMXCoreDesc -lLLVMXCoreInfo -lLLVMX86TargetMCA -lLLVMX86Disassembler -lLLVMX86AsmParser -lLLVMX86CodeGen -lLLVMX86Desc -lLLVMX86Info -lLLVMWebAssemblyDisassembler -lLLVMWebAssemblyAsmParser -lLLVMWebAssemblyCodeGen -lLLVMWebAssemblyUtils -lLLVMWebAssemblyDesc -lLLVMWebAssemblyInfo -lLLVMVEDisassembler -lLLVMVEAsmParser -lLLVMVECodeGen -lLLVMVEDesc -lLLVMVEInfo -lLLVMSystemZDisassembler -lLLVMSystemZAsmParser -lLLVMSystemZCodeGen -lLLVMSystemZDesc -lLLVMSystemZInfo -lLLVMSparcDisassembler -lLLVMSparcAsmParser -lLLVMSparcCodeGen -lLLVMSparcDesc -lLLVMSparcInfo -lLLVMRISCVTargetMCA -lLLVMRISCVDisassembler -lLLVMRISCVAsmParser -lLLVMRISCVCodeGen -lLLVMRISCVDesc -lLLVMRISCVInfo -lLLVMPowerPCDisassembler -lLLVMPowerPCAsmParser -lLLVMPowerPCCodeGen -lLLVMPowerPCDesc -lLLVMPowerPCInfo -lLLVMNVPTXCodeGen -lLLVMNVPTXDesc -lLLVMNVPTXInfo -lLLVMMSP430Disassembler -lLLVMMSP430AsmParser -lLLVMMSP430CodeGen -lLLVMMSP430Desc -lLLVMMSP430Info -lLLVMMipsDisassembler -lLLVMMipsAsmParser -lLLVMMipsCodeGen -lLLVMMipsDesc -lLLVMMipsInfo -lLLVMLoongArchDisassembler -lLLVMLoongArchAsmParser -lLLVMLoongArchCodeGen -lLLVMLoongArchDesc -lLLVMLoongArchInfo -lLLVMLanaiDisassembler -lLLVMLanaiCodeGen -lLLVMLanaiAsmParser -lLLVMLanaiDesc -lLLVMLanaiInfo -lLLVMHexagonDisassembler -lLLVMHexagonCodeGen -lLLVMHexagonAsmParser -lLLVMHexagonDesc -lLLVMHexagonInfo -lLLVMBPFDisassembler -lLLVMBPFAsmParser -lLLVMBPFCodeGen -lLLVMBPFDesc -lLLVMBPFInfo -lLLVMAVRDisassembler -lLLVMAVRAsmParser -lLLVMAVRCodeGen -lLLVMAVRDesc -lLLVMAVRInfo -lLLVMARMDisassembler -lLLVMARMAsmParser -lLLVMARMCodeGen -lLLVMARMDesc -lLLVMARMUtils -lLLVMARMInfo -lLLVMAMDGPUTargetMCA -lLLVMAMDGPUDisassembler -lLLVMAMDGPUAsmParser -lLLVMAMDGPUCodeGen -lLLVMAMDGPUDesc -lLLVMAMDGPUUtils -lLLVMAMDGPUInfo -lLLVMAArch64Disassembler -lLLVMAArch64AsmParser -lLLVMAArch64CodeGen -lLLVMAArch64Desc -lLLVMAArch64Utils -lLLVMAArch64Info -lLLVMOrcDebugging -lLLVMOrcJIT -lLLVMWindowsDriver -lLLVMMCJIT -lLLVMJITLink -lLLVMInterpreter -lLLVMExecutionEngine -lLLVMRuntimeDyld -lLLVMOrcTargetProcess -lLLVMOrcShared -lLLVMDWP -lLLVMDebugInfoLogicalView -lLLVMDebugInfoGSYM -lLLVMOption -lLLVMObjectYAML -lLLVMObjCopy -lLLVMMCA -lLLVMMCDisassembler -lLLVMLTO -lLLVMPasses -lLLVMHipStdPar -lLLVMCFGuard -lLLVMCoroutines -lLLVMipo -lLLVMVectorize -lLLVMLinker -lLLVMInstrumentation -lLLVMFrontendOpenMP -lLLVMFrontendOffloading -lLLVMFrontendOpenACC -lLLVMFrontendHLSL -lLLVMFrontendDriver -lLLVMExtensions -lLLVMDWARFLinkerParallel -lLLVMDWARFLinkerClassic -lLLVMDWARFLinker -lLLVMCodeGenData -lLLVMGlobalISel -lLLVMMIRParser -lLLVMAsmPrinter -lLLVMSelectionDAG -lLLVMCodeGen -lLLVMTarget -lLLVMObjCARCOpts -lLLVMCodeGenTypes -lLLVMIRPrinter -lLLVMInterfaceStub -lLLVMFileCheck -lLLVMFuzzMutate -lLLVMScalarOpts -lLLVMInstCombine -lLLVMAggressiveInstCombine -lLLVMTransformUtils -lLLVMBitWriter -lLLVMAnalysis -lLLVMProfileData -lLLVMSymbolize -lLLVMDebugInfoBTF -lLLVMDebugInfoPDB -lLLVMDebugInfoMSF -lLLVMDebugInfoDWARF -lLLVMObject -lLLVMTextAPI -lLLVMMCParser -lLLVMIRReader -lLLVMAsmParser -lLLVMMC -lLLVMDebugInfoCodeView -lLLVMBitReader -lLLVMFuzzerCLI -lLLVMCore -lLLVMRemarks -lLLVMBitstreamReader -lLLVMBinaryFormat -lLLVMTargetParser -lLLVMSupport -lLLVMDemangle -lz -I/opt/homebrew/opt/zstd/include -L/opt/homebrew/opt/zstd/lib -lzstd -fno-sanitize-thread -OReleaseSafe -target aarch64-macos -mcpu apple_m3 --dep aro --dep aro_translate_c --dep build_options -Mroot=zig/src/main.zig -Maro=zig/lib/compiler/aro/aro.zig --dep aro -Maro_translate_c=zig/lib/compiler/aro_translate_c.zig -Mbuild_options=zig/.zig-cache/c/17da5134cc20c237ea498d8a65707e3c/options.zig -lc++ -lc --cache-dir zig/.zig-cache --global-cache-dir /Users/alwin/.cache/zig --name zig -L out/aarch64-macos-apple_m3/lib -I out/aarch64-macos-apple_m3/include --zig-lib-dir out/host/lib/zig/ --listen=-
```

This command provide a clue.
The other  clue is given by the zig-espressif-bootstrap maintainer on Zig's repository [issue tracker](https://github.com/ziglang/zig/issues/5467#issuecomment-1951434376).

The LLVM libraries declaration in `build.zig` is missing the following libraries:

```
    "LLVMXtensaAsmParser",
    "LLVMXtensaDesc",
    "LLVMXtensaInfo",
    "LLVMXtensaCodeGen",
    "LLVMXtensaDisassembler",
```

Adding those libraries to the `llvm_libs` in the `build.zig` file solves the linker problem.

#### ESP32 Is Not Recognized

Compiling the test code for `esp32` CPU using the previously built Zig produces the same error.

```
./out/zig-$TARGET-$MCPU/zig cc -S -O1 -target xtensa-freestanding-none -mcpu=esp32 test.c
```

```
info: available CPUs for architecture 'xtensa':
 generic

error: unknown CPU: 'esp32'
```

Enabling Xtensa target on Espressif's fork of LLVM was not enough.

#### Updating Zig's Xtensa Targets Definition

The target definition is available at `lib/std/Targets/xtensa.zig`.
```zig
//! This file is auto-generated by tools/update_cpu_features.zig.

const std = @import("../std.zig");
const CpuFeature = std.Target.Cpu.Feature;
const CpuModel = std.Target.Cpu.Model;

pub const Feature = enum {
    density,
};

pub const featureSet = CpuFeature.FeatureSetFns(Feature).featureSet;
pub const featureSetHas = CpuFeature.FeatureSetFns(Feature).featureSetHas;
pub const featureSetHasAny = CpuFeature.FeatureSetFns(Feature).featureSetHasAny;
pub const featureSetHasAll = CpuFeature.FeatureSetFns(Feature).featureSetHasAll;

pub const all_features = blk: {
    const len = @typeInfo(Feature).@"enum".fields.len;
    std.debug.assert(len <= CpuFeature.Set.needed_bit_count);
    var result: [len]CpuFeature = undefined;
    result[@intFromEnum(Feature.density)] = .{
        .llvm_name = "density",
        .description = "Enable Density instructions",
        .dependencies = featureSet(&[_]Feature{}),
    };
    const ti = @typeInfo(Feature);
    for (&result, 0..) |*elem, i| {
        elem.index = i;
        elem.name = ti.@"enum".fields[i].name;
    }
    break :blk result;
};

pub const cpu = struct {
    pub const generic: CpuModel = .{
        .name = "generic",
        .llvm_name = "generic",
        .features = featureSet(&[_]Feature{}),
    };
};
```

This file shows that:
- The CPUs are not synced with the Espressif's LLVM fork.
- This file is auto-generated by `tools/update_cpu_features.zig`.

We can use the `$ZIG build-exe` command to build the tool.

```sh
$ZIG build-exe zig/tools/update_cpu_features.zig
```

Then we can use the `update_cpu_features` tool.

```
./update_cpu_features out/build-llvm-TARGET-$MCPU/bin/llvm-tblgen . zig
```

The first argument is the path to llvm-tblgen executable.
The second argument is the path to the directory that contains `llvm` directory.
The third argument is the path to the zig source code.

The Xtensa target will be updated and synced with its LLVM counterpart once we run the tool.

Then we can rebuild the Zig cross compiler and the Zig toolchain for the target architecture.
We need to make sure that the cache are cleared and the previous build result are deleted.

```sh
rm -rf out/zig-$TARGET-$MCPU
rm -rf zig/.zig-cache
```

```sh
cd $ROOTDIR/build-zig-host
cmake "$ROOTDIR/zig" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_VERSION="$ZIG_VERSION"
cmake --build . --target install
```

```sh
cd $ROOTDIR/zig
$ZIG build \
  --prefix "$ROOTDIR/out/zig-$TARGET-$MCPU" \
  --search-prefix "$ROOTDIR/out/$TARGET-$MCPU" \
  -Dflat \
  -Dllvm-has-xtensa \
  -Dstatic-llvm \
  -Doptimize=ReleaseSafe \
  -Dtarget="$TARGET" \
  -Dcpu="$MCPU" \
  -Dversion-string="$ZIG_VERSION"
```

I encountered exceeded maximum memory usage error on the last step.
The error disappear if we re-run the Zig build command.

#### Fixing LLVM Bindings and Xtensa Target Initialization

Testing the Zig C compiler again, we can now generate code for ESP32!

```
$ROOTDIR/out/zig-$TARGET-$MCPU/zig cc -S -O1 test.c -target xtensa-freestanding-none -mcpu=esp32
```

Now we test Zig code compilation for ESP32.
I created a `test.zig` file that is very similar to the `test.c` file:

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Then I used the `build-obj` command and `-femit-asm` flag to emit an assembly file.

```
$ROOTDIR/out/zig-$TARGET-$MCPU/zig build-obj -femit-asm test.zig -target xtensa-freestanding-none -mcpu=esp32
```

It produced the following error instead of object and assembly file.

```
error: LLVM failed to emit bin=test.o.o ir=(none): TargetMachine can't emit an object file
```

If I changed the `build-obj` to `build-exe`, it generated different LLVM error message:

```
error: sub-compilation of compiler_rt failed
    note: LLVM failed to emit asm=(none) bin=/Users/alwin/.cache/zig/o/f668107cca09af86409f928796acbde8/libcompiler_rt.a.o ir=(none) bc=(none): TargetMachine can't emit an object file
```

I looked at the `src/codegen/llvm.zig` file and search for `xtensa` until I found the following snippet:

```zig
pub fn initializeLLVMTarget(arch: std.Target.Cpu.Arch) void {
    switch (arch) {
        // ...
        .xtensa => {
            if (build_options.llvm_has_xtensa) {
                llvm.LLVMInitializeXtensaTarget();
                llvm.LLVMInitializeXtensaTargetInfo();
                llvm.LLVMInitializeXtensaTargetMC();
                // There is no LLVMInitializeXtensaAsmPrinter function.
                llvm.LLVMInitializeXtensaAsmParser();
            }
        },
        // ...
    }
}
```

This function initializes LLVM target for the specific architecture.
In this case, the Zig code generation feature initializes the Xtensa target and the `LLVMInitializeXtensaAsmPrinter` function was not called.
This caused the code generation to fail.

The `llvm.LLVMInitializeXtensaAsmPrinter();` is added to the code.

```zig
        .xtensa => {
            if (build_options.llvm_has_xtensa) {
                llvm.LLVMInitializeXtensaTarget();
                llvm.LLVMInitializeXtensaTargetInfo();
                llvm.LLVMInitializeXtensaTargetMC();
                llvm.LLVMInitializeXtensaAsmPrinter();
                llvm.LLVMInitializeXtensaAsmParser();
            }
        },
```

Attempting to rebuilt the Zig toolchain caused the following error:

```
src/codegen/llvm.zig:13020:21: error: root source file struct 'codegen.llvm.bindings' has no member named 'LLVMInitializeXtensaAsmPrinter'
                llvm.LLVMInitializeXtensaAsmPrinter();
```

The bindings in `src/codegen/llvm/bindings.zig` is missing an external function declaration to the `LLVMInitializeXtensaAsmPrinter` function.

```zig
pub extern fn LLVMInitializeXtensaAsmPrinter() void;
```

With these changes in place, we can have a working Zig toolchain that compiles Zig code for ESP32.

```
$ROOTDIR/out/zig-$TARGET-$MCPU/zig build-obj -femit-asm test.zig -target xtensa-freestanding-none -mcpu=esp32
```

## Summary: Required Changes to Support Xtensa ESP32

To successfully add Xtensa ESP32 support to Zig, you need to make the following changes to the Zig codebase:

1. **Update CPU Features**: Run the `update_cpu_features.zig` tool to synchronize Zig's CPU features with LLVM's target description for Xtensa

   ```sh
   ./update_cpu_features /path/to/llvm-tblgen /path/to/llvm-project /path/to/zig
   ```

   This will update `lib/std/Target/xtensa.zig` to include ESP32 CPU support.

2. **Add Missing LLVM Libraries**: Modify `build.zig` to include the following Xtensa-specific LLVM libraries:

   ```zig
   "LLVMXtensaAsmParser",
   "LLVMXtensaDesc",
   "LLVMXtensaInfo",
   "LLVMXtensaCodeGen",
   "LLVMXtensaDisassembler",
   ```

3. **Add Missing LLVM AsmPrinter Function**: Add this function declaration to `src/codegen/llvm/bindings.zig`:

   ```zig
   pub extern fn LLVMInitializeXtensaAsmPrinter() void;
   ```

4. **Update LLVM Target Initialization**: Modify the Xtensa case in `src/codegen/llvm.zig` to include the AsmPrinter:

   ```zig
   .xtensa => {
       if (build_options.llvm_has_xtensa) {
           llvm.LLVMInitializeXtensaTarget();
           llvm.LLVMInitializeXtensaTargetInfo();
           llvm.LLVMInitializeXtensaTargetMC();
           llvm.LLVMInitializeXtensaAsmPrinter(); // Add this line
           llvm.LLVMInitializeXtensaAsmParser();
       }
   },
   ```

5. **Build with Xtensa Support**: When building Zig, make sure to use the `-Dllvm-has-xtensa` build option.

After making these changes, Zig should be able to correctly recognize the ESP32 CPU and generate code for the Xtensa architecture.
