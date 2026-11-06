#!/bin/bash
# Builds and runs the semantic-cleanup race tests.
#
# The tests fail on purpose until diff_cleanupSemanticScore compiles its
# POSIX regexes exactly once and does not call regexec until that finishes.
#
# Commands:
#   Tests/run_semantic_cleanup_race.sh
#
# Packages used on Linux: clang, gnustep-make, libgnustep-base-dev,
# libicu-dev, libblocksruntime-dev, libobjc-13-dev.
#
# CoreBase is GNUstep libs-corebase commit 67a6f90601e7b143f173d1403f9a381a6d968fc2
# (the CFString/CFCharacterSet implementation linked into this test). It is
# cloned into /tmp and not part of this repository.
#
# Not covered here, because this CoreBase/GNUstep combination crashes inside
# string creation before those calls return:
#   diff_main line mode (DiffMatchPatch.m:546-548 and :584) dies in
#   diff_cleanupMerge's string append (DiffMatchPatch.m:1117) via GNUstep Base.
#   patch_apply's imperfect match (DiffMatchPatch.m:2383) dies in
#   CFStringCreateWithSubstring (CoreBase CFString.c:669) before
#   diff_cleanupSemanticLossless at DiffMatchPatch.m:2402.
# Both of those methods call the same diff_cleanupSemantic /
# diff_cleanupSemanticLossless paths the tests below race.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COREBASE_SRC="${COREBASE_SRC:-/tmp/libs-corebase}"
COREBASE_REV="67a6f90601e7b143f173d1403f9a381a6d968fc2"
SUPPORT="$ROOT/Tests/support"
OBJCINC="/usr/lib/gcc/x86_64-linux-gnu/13/include"
WORK="${TMPDIR:-/tmp}/semantic-cleanup-race"
mkdir -p "$WORK"

if [[ ! -f "$COREBASE_SRC/Source/obj/libgnustep-corebase.so" ]]; then
  rm -rf "$COREBASE_SRC"
  git clone --depth 1 https://github.com/gnustep/libs-corebase.git "$COREBASE_SRC"
  git -C "$COREBASE_SRC" fetch --depth 1 origin "$COREBASE_REV"
  git -C "$COREBASE_SRC" checkout --detach "$COREBASE_REV"
  (
    cd "$COREBASE_SRC"
    # shellcheck disable=SC1091
    set +u
    . /usr/share/GNUstep/Makefiles/GNUstep.sh
    set -u
    ./configure --without-gcd
    make -j"$(nproc)"
  )
fi

# shellcheck disable=SC1091
set +u
. /usr/share/GNUstep/Makefiles/GNUstep.sh
set -u

FLAGS="$(gnustep-config --objc-flags) -DDEBUG_ASSERT_PRODUCTION_CODE=1 -D_GNU_SOURCE"
FLAGS="$FLAGS -I$ROOT -I$COREBASE_SRC/Headers -I/usr/include/GNUstep -I$SUPPORT -I$OBJCINC"
FLAGS="$FLAGS -include $SUPPORT/tokenizer_compat.h -include $SUPPORT/AssertMacros.h"
FLAGS="$FLAGS -Wno-deprecated-declarations -fno-objc-arc -fno-strict-aliasing"
FLAGS="$FLAGS -ffunction-sections -fdata-sections"

clang -std=c99 $FLAGS -c "$ROOT/DiffMatchPatchCFUtilities.c" -o "$WORK/DiffMatchPatchCFUtilities.o"
clang $FLAGS -c "$ROOT/DiffMatchPatch.m" -o "$WORK/DiffMatchPatch.o"
clang $FLAGS -c "$ROOT/NSString+JavaSubstring.m" -o "$WORK/JavaSubstring.o"
clang $FLAGS -c "$ROOT/NSString+UriCompatibility.m" -o "$WORK/UriCompatibility.o"
clang $FLAGS -c "$ROOT/NSMutableDictionary+DMPExtensions.m" -o "$WORK/DMPExtensions.o"
clang -std=c99 $FLAGS -c "$SUPPORT/tokenizer_stubs.c" -o "$WORK/tokenizer_stubs.o"
clang $FLAGS -c "$ROOT/Tests/SemanticCleanupRaceTests.m" -o "$WORK/SemanticCleanupRaceTests.o"

clang "$WORK/SemanticCleanupRaceTests.o" \
  "$WORK/DiffMatchPatch.o" \
  "$WORK/JavaSubstring.o" \
  "$WORK/UriCompatibility.o" \
  "$WORK/DMPExtensions.o" \
  "$WORK/DiffMatchPatchCFUtilities.o" \
  "$WORK/tokenizer_stubs.o" \
  $(gnustep-config --base-libs) \
  -L"$OBJCINC/.." \
  -L"$COREBASE_SRC/Source/obj" -lgnustep-corebase \
  -Wl,--gc-sections -Wl,--wrap=regcomp -Wl,--wrap=regexec \
  -Wl,-rpath,"$COREBASE_SRC/Source/obj" \
  -o "$WORK/semantic_cleanup_race_tests"

"$WORK/semantic_cleanup_race_tests"
