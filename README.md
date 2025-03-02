# Making Zig Generate Code for Espressif Chips

## Background

If you are not coming from an embedded systems or IoT background, you must be wondering what is this all about and why did I do this.

Espressif is a company in China that makes chips mainly for IoT applications.
They have a very popular line of chips called ESP32, which is used in many projects and available worldwide since around 2016.
The ESP32 is a dual-core microcontroller with Wi-Fi and Bluetooth capabilities, making it top choice for IoT applications among hobbyists and professionals alike.
Espressif develop and maintain an SDK called ESP-IDF (Espressif IoT Development Framework) that is used to develop applications.
They also provide an Arduino core that allows hobbyists and makers to use the Arduino framework and libraries to develop applications.

Both the ESP-IDF and Arduino core are written in C and C++. While C and C++ are the common languages used in embedded systems, with the rise of
Rust and Zig, I wondered if it was possible to use Zig to develop applications for the ESP32.
Espressif already have a working Rust toolchain based on their fork of the LLVM project, and per today we can use Rust to target ESP32 chips, but I'm not interested in Rust at this point.
Since both Zig and Rust uses LLVM backend to generate code for the target machines, so it should be possible to some extent to use Zig as one of the language for
developing embedded systems or IoT application for ESP32 chips.

## Zig for ESP32

Yes, someone has already done it and it's available at [github.com/kassane/zig-espressif-bootstrap](github.com/kassane/zig-espressif-bootstrap).
It's a fork of the official repo for bootstrapping Zig for different machines (e.g., you're on Apple Silicon Mac but you want to distribute Zig for x86 Linux).
The main difference between those repo is of course the availability of the Xtensa in the LLVM backend.
The zig-espressif-bootstrap uses Espressif's port of LLVM project to build the Zig toolchain.
Sound simple? Well...

Unfortunately, Espressif's fork of LLVM project is NOT the only thing needed to make Zig compiler able to generate code for the Xtensa target.
To make it even worse, the zig-espressif-bootstrap's maintainer does not provide a clear documentation on how he did it.
But, they did give some clue somewhere else.
This led me to a journey with lots of headaches and a relieving sense of victory after figuring it out.

So, if you're looking to get a working Zig compiler that has a support for Xtensa architecture, go use the zig-espressif-bootstrap.
But, if you're like me, curious about how things works under the hood, then read on.

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

Bootstrapping for different machine and adding experimental LLVM target (like Xtensa) is different kind of beast, though.

### Bootstrapping for Different Machine

Using zig-bootstrap repo involves different kind of activity, here's the summary:

1. Build the LLVM project including LLVM backend, LLD, and Clang with few features turned off using the system's C and C++ compiler.
2. Build the Zig cross compiler with the previously built LLVM using the system's C and C++ compiler.
3. Build the zlib and zstd for the target machine using Zig cross compiler.
4. Rebuild the LLVM using Zig cross compiler for the target machine.
5. Rebuild the Zig using the rebuilt LLVM and the Zig cross compiler in the previous step for the target machine.

You can confirm this by looking at the shell script (`build`) in the [ziglang/zig-bootstrap](github.com/ziglang/zig-bootstrap) repo.
The zig-bootstrap repo, both the upstream and the fork that includes Xtensa support, provides all dependencies source code locally (except CMake and the C and C++ compiler).
This is convenient because we don't need to get and install all of those separately.

At the end of the step, we'll have a working Zig toolchain for the target machine.
Sounds good, right?
Now here comes the part where I got hours of headaches.

### Journey: Building with Xtensa Support

Building LLVM with Xtensa support requires an additional CMake option to be passed into its CLI.

```sh
-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa
```

Here's an excerpt from zig-espressif-bootstrap for the complete CMake options:

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

The above script covers the step number 1 that we described in the [Bootstrapping for Different Machine](#bootstrapping-for-different-machine) section.

For LLVM, adding the `-DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD=Xtensa` is enough.
But, is it enough for Zig? That will be answered later on.

Moving to step 2, we can build the Zig toolchain with the previously built LLVM.

```sh
cmake "$ROOTDIR/zig" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_VERSION="$ZIG_VERSION"
cmake --build . --target install
```

Nothing strange, but here we build Zig without regard of the Xtensa because we only need Zig as a cross-compiler here. Although we can try the code generation using `zig cc` with the following code:

```c
// filename: test.c
int add(int a, int b) {
    return a + b;
}
```

```sh
$ROOT_DIR/out/host/bin/zig cc -S test.c -target xtensa-frestanding-none -O1
```

Then it will produce the following file, truncated for brevity:

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

But, this is for _generic_ CPU, not specific to ESP32. If we attempt to add `-mcpu=esp32` option like the following shell script, it will yield error.

```sh
$ROOT_DIR/out/host/bin/zig cc -S test.c -target xtensa-frestanding-none -O1 -mcpu=esp32
```

```
info: available CPUs for architecture 'xtensa':
 generic

error: unknown CPU: 'esp32'
```

Interestingly, if we build LLVM and Clang that enables Xtensa and compile the same `test.c` code using clang, it will compile successfully and generate the following assembly code.

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

This is part of the problem that caused headache for at least two straight hours for me, but we'll revisit it later down the line.
Mainly, because I didn't really understand how LLVM works, and I didn't understand how Zig uses LLVM under the hood. In fact, I have yet to fully understand how they work.

Anyway, compiling zstd and zlib is pretty straightforward. Here we use the Zig cross compiler to compile those C projects as static library.

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

Then, we use the static libraries to rebuild the LLVM for the target machine. This build will use the zstd and zlib, and also uses llvm-tblgen and clang-tblgen target-specific code generation.
We'll come back to the tablegen later on (psst, it's kind of related to the esp32 not appearing as a valid CPU for Xtensa target).

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

Building LLVM for the second time in this entire process yields successful result, the number of object files generated is even lesser than the first LLVM build.

Then in the final step, we build the Zig toolchain using Zig with the previously built LLVM.

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

The Zig toolchain pointed by environment variable `$ZIG` was compiled using CMake, the cross-compiled Zig was built using Zig Build System as incidated by the `$ZIG build` command.
It uses the target installation directories to search for its dependencies, especially LLVM and zstd, in the `$ROOTDIR/out/$TARGET-$MCPU` directory.

Here we use the `-Dflat` argument to make the Zig toolchain directory structured as follow:

```
zig-$TARGET-$MCPU
├── LICENSE
├── README.md
├── doc
│   └── langref.html
├── lib
└── zig
```

Then, we used the `ReleaseSafe` build mode.
By definition, that mode ensures that whatever executable produced by the Zig toolchain has runtime safety checks.
One interesting flag is the `-Dllvm-has-xtensa`, it enables the LLVM target for Zig.

Long story short, the compilation failed at linking step.
The error message said that it missed the following symbols and where it was referenced

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

It seems like the `$ZIG` cross compiler was missing the symbols related to Xtensa target from LLVM.
The symbols should be available since we enabled the Xtensa target on LLVM.

More on the failing command:

```
out/host/bin/zig build-exe --stack 48234496 -cflags -std=c++17 -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS -D__STDC_LIMIT_MACROS -D_GNU_SOURCE -fno-exceptions -fno-rtti -fno-stack-protector -fvisibility-inlines-hidden -Wno-type-limits -Wno-missing-braces -Wno-comment -DNDEBUG=1 -- zig/src/zig_llvm.cpp zig/src/zig_clang.cpp zig/src/zig_llvm-ar.cpp zig/src/zig_clang_driver.cpp zig/src/zig_clang_cc1_main.cpp zig/src/zig_clang_cc1as_main.cpp -lclangFrontendTool -lclangCodeGen -lclangFrontend -lclangDriver -lclangSerialization -lclangSema -lclangStaticAnalyzerFrontend -lclangStaticAnalyzerCheckers -lclangStaticAnalyzerCore -lclangAnalysis -lclangASTMatchers -lclangAST -lclangParse -lclangAPINotes -lclangBasic -lclangEdit -lclangLex -lclangARCMigrate -lclangRewriteFrontend -lclangRewrite -lclangCrossTU -lclangIndex -lclangToolingCore -lclangExtractAPI -lclangSupport -lclangInstallAPI -llldMinGW -llldELF -llldCOFF -llldWasm -llldMachO -llldCommon -lLLVMWindowsManifest -lLLVMXRay -lLLVMLibDriver -lLLVMDlltoolDriver -lLLVMTextAPIBinaryReader -lLLVMCoverage -lLLVMLineEditor -lLLVMSandboxIR -lLLVMXCoreDisassembler -lLLVMXCoreCodeGen -lLLVMXCoreDesc -lLLVMXCoreInfo -lLLVMX86TargetMCA -lLLVMX86Disassembler -lLLVMX86AsmParser -lLLVMX86CodeGen -lLLVMX86Desc -lLLVMX86Info -lLLVMWebAssemblyDisassembler -lLLVMWebAssemblyAsmParser -lLLVMWebAssemblyCodeGen -lLLVMWebAssemblyUtils -lLLVMWebAssemblyDesc -lLLVMWebAssemblyInfo -lLLVMVEDisassembler -lLLVMVEAsmParser -lLLVMVECodeGen -lLLVMVEDesc -lLLVMVEInfo -lLLVMSystemZDisassembler -lLLVMSystemZAsmParser -lLLVMSystemZCodeGen -lLLVMSystemZDesc -lLLVMSystemZInfo -lLLVMSparcDisassembler -lLLVMSparcAsmParser -lLLVMSparcCodeGen -lLLVMSparcDesc -lLLVMSparcInfo -lLLVMRISCVTargetMCA -lLLVMRISCVDisassembler -lLLVMRISCVAsmParser -lLLVMRISCVCodeGen -lLLVMRISCVDesc -lLLVMRISCVInfo -lLLVMPowerPCDisassembler -lLLVMPowerPCAsmParser -lLLVMPowerPCCodeGen -lLLVMPowerPCDesc -lLLVMPowerPCInfo -lLLVMNVPTXCodeGen -lLLVMNVPTXDesc -lLLVMNVPTXInfo -lLLVMMSP430Disassembler -lLLVMMSP430AsmParser -lLLVMMSP430CodeGen -lLLVMMSP430Desc -lLLVMMSP430Info -lLLVMMipsDisassembler -lLLVMMipsAsmParser -lLLVMMipsCodeGen -lLLVMMipsDesc -lLLVMMipsInfo -lLLVMLoongArchDisassembler -lLLVMLoongArchAsmParser -lLLVMLoongArchCodeGen -lLLVMLoongArchDesc -lLLVMLoongArchInfo -lLLVMLanaiDisassembler -lLLVMLanaiCodeGen -lLLVMLanaiAsmParser -lLLVMLanaiDesc -lLLVMLanaiInfo -lLLVMHexagonDisassembler -lLLVMHexagonCodeGen -lLLVMHexagonAsmParser -lLLVMHexagonDesc -lLLVMHexagonInfo -lLLVMBPFDisassembler -lLLVMBPFAsmParser -lLLVMBPFCodeGen -lLLVMBPFDesc -lLLVMBPFInfo -lLLVMAVRDisassembler -lLLVMAVRAsmParser -lLLVMAVRCodeGen -lLLVMAVRDesc -lLLVMAVRInfo -lLLVMARMDisassembler -lLLVMARMAsmParser -lLLVMARMCodeGen -lLLVMARMDesc -lLLVMARMUtils -lLLVMARMInfo -lLLVMAMDGPUTargetMCA -lLLVMAMDGPUDisassembler -lLLVMAMDGPUAsmParser -lLLVMAMDGPUCodeGen -lLLVMAMDGPUDesc -lLLVMAMDGPUUtils -lLLVMAMDGPUInfo -lLLVMAArch64Disassembler -lLLVMAArch64AsmParser -lLLVMAArch64CodeGen -lLLVMAArch64Desc -lLLVMAArch64Utils -lLLVMAArch64Info -lLLVMOrcDebugging -lLLVMOrcJIT -lLLVMWindowsDriver -lLLVMMCJIT -lLLVMJITLink -lLLVMInterpreter -lLLVMExecutionEngine -lLLVMRuntimeDyld -lLLVMOrcTargetProcess -lLLVMOrcShared -lLLVMDWP -lLLVMDebugInfoLogicalView -lLLVMDebugInfoGSYM -lLLVMOption -lLLVMObjectYAML -lLLVMObjCopy -lLLVMMCA -lLLVMMCDisassembler -lLLVMLTO -lLLVMPasses -lLLVMHipStdPar -lLLVMCFGuard -lLLVMCoroutines -lLLVMipo -lLLVMVectorize -lLLVMLinker -lLLVMInstrumentation -lLLVMFrontendOpenMP -lLLVMFrontendOffloading -lLLVMFrontendOpenACC -lLLVMFrontendHLSL -lLLVMFrontendDriver -lLLVMExtensions -lLLVMDWARFLinkerParallel -lLLVMDWARFLinkerClassic -lLLVMDWARFLinker -lLLVMCodeGenData -lLLVMGlobalISel -lLLVMMIRParser -lLLVMAsmPrinter -lLLVMSelectionDAG -lLLVMCodeGen -lLLVMTarget -lLLVMObjCARCOpts -lLLVMCodeGenTypes -lLLVMIRPrinter -lLLVMInterfaceStub -lLLVMFileCheck -lLLVMFuzzMutate -lLLVMScalarOpts -lLLVMInstCombine -lLLVMAggressiveInstCombine -lLLVMTransformUtils -lLLVMBitWriter -lLLVMAnalysis -lLLVMProfileData -lLLVMSymbolize -lLLVMDebugInfoBTF -lLLVMDebugInfoPDB -lLLVMDebugInfoMSF -lLLVMDebugInfoDWARF -lLLVMObject -lLLVMTextAPI -lLLVMMCParser -lLLVMIRReader -lLLVMAsmParser -lLLVMMC -lLLVMDebugInfoCodeView -lLLVMBitReader -lLLVMFuzzerCLI -lLLVMCore -lLLVMRemarks -lLLVMBitstreamReader -lLLVMBinaryFormat -lLLVMTargetParser -lLLVMSupport -lLLVMDemangle -lz -I/opt/homebrew/opt/zstd/include -L/opt/homebrew/opt/zstd/lib -lzstd -fno-sanitize-thread -OReleaseSafe -target aarch64-macos -mcpu apple_m3 --dep aro --dep aro_translate_c --dep build_options -Mroot=zig/src/main.zig -Maro=zig/lib/compiler/aro/aro.zig --dep aro -Maro_translate_c=zig/lib/compiler/aro_translate_c.zig -Mbuild_options=zig/.zig-cache/c/17da5134cc20c237ea498d8a65707e3c/options.zig -lc++ -lc --cache-dir zig/.zig-cache --global-cache-dir /Users/alwin/.cache/zig --name zig -L out/aarch64-macos-apple_m3/lib -I out/aarch64-macos-apple_m3/include --zig-lib-dir out/host/lib/zig/ --listen=-
```

This lengthy command provide one of two clues around the linking issue.
The other clue is provided by the zig-espressif-bootstrap maintainer on Zig's upstream repository issue tracker. You can check it on this [comment](https://github.com/ziglang/zig/issues/5467#issuecomment-1951434376).

They said, that the `build.zig` file is missing the following libraries:

```
    "LLVMXtensaAsmParser",
    "LLVMXtensaDesc",
    "LLVMXtensaInfo",
    "LLVMXtensaCodeGen",
    "LLVMXtensaDisassembler",
```

They're right, if we inspect the failing command, we don't see those libraries.
We need to add those libraries to the `llvm_libs` in the `build.zig` file.
After this we can re-run the Zig cross-compilation process again and see that it now compiles successfully.

Hooray? No.

Try compiling the test code again with `-mcpu=esp32`

```
./out/zig-$TARGET-$MCPU/zig cc -S -O1 -target xtensa-freestanding-none -mcpu=esp32 test.c
```

Then we still get the following error:

```
info: available CPUs for architecture 'xtensa':
 generic

error: unknown CPU: 'esp32'
```

Well, this is what I mean by enabling Xtensa target for LLVM and using Espressif's fork of it was not enough.
It seems like the targets on LLVM is not directly _mirrored_ by Zig.
So I had to dig on Zig's targets and I found the following definition of the Xtensa target in `lib/std/Targets/xtensa.zig`.

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

I learned two things:

- There's only `generic` CPU as expected, this file clearly was not _synced_ with Espressif's port of LLVM.
- The very first line, `//! This file is auto-generated by tools/update_cpu_features.zig.`. Oh, there's a tool for that? Neat.

We can use the `$ZIG build-exe` command to build the tool.

```sh
./out/host/bin/zig build-exe zig/tools/update_cpu_features.zig
```

It will produce the update_cpu_features executable which upon execution without additional arguments yield the following output:

```
Usage: ./update_cpu_features /path/to/llvm-tblgen /path/git/llvm-project /path/git/zig [zig_name filter]

Updates lib/std/target/<target>.zig from llvm/lib/Target/<Target>/<Target>.td .

On a less beefy system, or when debugging, compile with -fsingle-threaded.
```

The first argument to the command can be provided as `out/build-llvm-$TARGET-$MCPU/bin/llvm-tblgen`.
The second argument is a path to directory that has a LLVM project directory. If you're on the zig-bootstrap project directory we can use `.` as the path to the directory. Lastly, we provide the path to the zig source code.

If we successfully updated the CPU features, we can see now that the `lib/std/Target/xtensa.zig` is now synchronized with its LLVM counterpart.

We can now rebuild the Zig.
But we have to make sure that we removed the previously built Zig and cleared the cache.

```sh
rm -rf out/zig-$TARGET-$MCPU
rm -rf zig/.zig-cache
```

Here we need to rebuild the Zig cross-compiler and the final Zig toolchain.
So we have to repeat the step 2 and the final step.

```sh
cd $ROOTDIR/build-zig-host
cmake "$ROOTDIR/zig" \
  -DCMAKE_INSTALL_PREFIX="$ROOTDIR/out/host" \
  -DCMAKE_PREFIX_PATH="$ROOTDIR/out/host" \
  -DCMAKE_BUILD_TYPE=Release \
  -DZIG_VERSION="$ZIG_VERSION"
cmake --build . --target install
```

and

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

I encountered memory error on the last step.
Somehow the build process consumed more memory than I anticipated.
When the error appear, I just repeated the command and the Zig toolchain was compiled successfully.

Testing the Zig C compiler again, we can now generate code for ESP32!

```
$ROOTDIR/out/zig-$TARGET-$MCPU/zig cc -S -O1 test.c -target xtensa-freestanding-none -mcpu=esp32
```

But, I didn't want to write C.
I wanted to write Zig for ESP32, so I needed to verify whether the current Zig compiler can compile Zig code and generate machine code for ESP32.

I created a `test.zig` file that is very similar to the `test.c` file:

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

I compiled the code using `build-obj` command.

```
$ROOTDIR/out/zig-$TARGET-$MCPU/zig build-obj -femit-asm test.zig -target xtensa-freestanding-none -mcpu=esp32
```

But, that command yielded different kind of error

```
error: LLVM failed to emit bin=test.o.o ir=(none): TargetMachine can't emit an object file
```

If I changed the `build-obj` to `build-exe`, it generated different LLVM error message:

```
error: sub-compilation of compiler_rt failed
    note: LLVM failed to emit asm=(none) bin=/Users/alwin/.cache/zig/o/f668107cca09af86409f928796acbde8/libcompiler_rt.a.o ir=(none) bc=(none): TargetMachine can't emit an object file
```

This again led me to headaches and more exploration on the Zig source code until I stumbled upon the `src/codegen` folder.
I opened the `llvm.zig` code in that directory and searched the entire code with `xtensa` keyword until I found something interesting.

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

Then it clicked!
Of course there's no LLVMInitializeXtensaAsmPrinter on the LLVM upstream repository!
So I go on and changed that switch case into

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

I tried the last step of the entire build process again to rebuild the Zig with the previous changes.
But it produced error

```
src/codegen/llvm.zig:13020:21: error: root source file struct 'codegen.llvm.bindings' has no member named 'LLVMInitializeXtensaAsmPrinter'
                llvm.LLVMInitializeXtensaAsmPrinter();
```

I opened the `src/codegen/llvm/bindings.zig` file and found that indeed there was no
`LLVMInitializeXtensaAsmPrinter()` member function.
I added the following line to that file:

```zig
pub extern fn LLVMInitializeXtensaAsmPrinter() void;
```

I repeated the final step and tried to compile the Zig code for ESP32 for one last time.
And, it succeed!

```
$ROOTDIR/out/zig-$TARGET-$MCPU/zig build-obj -femit-asm test.zig -target xtensa-freestanding-none -mcpu=esp32
```

Now I have a working Zig toolchain that can compile Zig code for ESP32!

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
