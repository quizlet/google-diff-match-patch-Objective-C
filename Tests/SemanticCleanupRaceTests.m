/*
 * Spec tests for the process-global regex in diff_cleanupSemanticScore.
 *
 * These tests fail while the first-run flag is an unsynchronized boolean.
 * They pass only when both POSIX regexes are compiled once, and no regexec
 * runs until that compilation has finished. Re-reading the flag between the
 * check and regcomp is not enough: overlapping regcomp, or regexec while
 * regcomp is still on the stack, fails the test.
 *
 * Untested entry points that call the same function (this harness cannot
 * finish them; see the script header):
 *   - diff_mainOfOldString:andNewString: line mode (DiffMatchPatch.m:584)
 *   - patch_apply:toString: imperfect-match cleanup (DiffMatchPatch.m:2402)
 */

#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <pthread.h>
#import <regex.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>
#import <unistd.h>
#import <sys/wait.h>

#import "DiffMatchPatch.h"
#import "DiffMatchPatchCFUtilities.h"

int __real_regcomp(regex_t *preg, const char *pattern, int cflags);
int __real_regexec(const regex_t *preg, const char *string, size_t nmatch, regmatch_t pmatch[], int eflags);

enum {
  kThreads = 8,
  kExitOk = 0,
  kExitRace = 1,
  kExitNoRegcomp = 2,
  kExitNoRegexec = 3,
  kExitBadResult = 4
};

typedef struct {
  regex_t *preg;
  int active;
} RegexSlot;

static RegexSlot gSlots[4];
static int gSlotCount = 0;
static pthread_mutex_t gSlotLock = PTHREAD_MUTEX_INITIALIZER;
static pthread_mutex_t gRealLock = PTHREAD_MUTEX_INITIALIZER;
static int gOverlap = 0;
static int gUseDuringInit = 0;
static int gRegcompCalls = 0;
static int gRegexecCalls = 0;
static int gBadResult = 0;

static RegexSlot *SlotFor(regex_t *preg, int create) {
  pthread_mutex_lock(&gSlotLock);
  for (int i = 0; i < gSlotCount; i++) {
    if (gSlots[i].preg == preg) {
      pthread_mutex_unlock(&gSlotLock);
      return &gSlots[i];
    }
  }
  if (!create || gSlotCount >= 4) {
    pthread_mutex_unlock(&gSlotLock);
    return NULL;
  }
  RegexSlot *slot = &gSlots[gSlotCount++];
  slot->preg = preg;
  __atomic_store_n(&slot->active, 0, __ATOMIC_RELAXED);
  pthread_mutex_unlock(&gSlotLock);
  return slot;
}

int __wrap_regcomp(regex_t *preg, const char *pattern, int cflags) {
  RegexSlot *slot = SlotFor(preg, 1);
  int previous = __atomic_fetch_add(&slot->active, 1, __ATOMIC_ACQ_REL);
  if (previous > 0) {
    __atomic_store_n(&gOverlap, 1, __ATOMIC_RELAXED);
  }
  __atomic_fetch_add(&gRegcompCalls, 1, __ATOMIC_RELAXED);
  /* Widen the window the unsynchronized first-run flag already opens.
   * A lock or pthread_once around regcomp keeps the second thread out
   * of this function until the first call returns. */
  usleep(30000);
  pthread_mutex_lock(&gRealLock);
  int rc = __real_regcomp(preg, pattern, cflags);
  pthread_mutex_unlock(&gRealLock);
  __atomic_fetch_sub(&slot->active, 1, __ATOMIC_ACQ_REL);
  return rc;
}

int __wrap_regexec(const regex_t *preg, const char *string, size_t nmatch, regmatch_t pmatch[], int eflags) {
  RegexSlot *slot = SlotFor((regex_t *)preg, 0);
  if (slot != NULL && __atomic_load_n(&slot->active, __ATOMIC_ACQUIRE) > 0) {
    __atomic_store_n(&gUseDuringInit, 1, __ATOMIC_RELAXED);
  }
  __atomic_fetch_add(&gRegexecCalls, 1, __ATOMIC_RELAXED);
  pthread_mutex_lock(&gRealLock);
  int rc = __real_regexec(preg, string, nmatch, pmatch, eflags);
  pthread_mutex_unlock(&gRealLock);
  return rc;
}

static void WarmCharacterSets(void) {
  (void)CFCharacterSetGetPredefined(kCFCharacterSetAlphaNumeric);
  (void)CFCharacterSetGetPredefined(kCFCharacterSetWhitespaceAndNewline);
  (void)CFCharacterSetGetPredefined(kCFCharacterSetControl);
}

static NSString *CFString(const char *bytes) {
  return (NSString *)CFStringCreateWithCString(kCFAllocatorDefault, bytes, kCFStringEncodingASCII);
}

static int ChildStatus(void) {
  if (__atomic_load_n(&gOverlap, __ATOMIC_RELAXED) || __atomic_load_n(&gUseDuringInit, __ATOMIC_RELAXED)) {
    return kExitRace;
  }
  if (__atomic_load_n(&gRegcompCalls, __ATOMIC_RELAXED) < 2) {
    return kExitNoRegcomp;
  }
  if (__atomic_load_n(&gRegexecCalls, __ATOMIC_RELAXED) < 1) {
    return kExitNoRegexec;
  }
  if (__atomic_load_n(&gBadResult, __ATOMIC_RELAXED)) {
    return kExitBadResult;
  }
  return kExitOk;
}

static void ExpectScore(CFIndex score, CFIndex want) {
  if (score != want) {
    __atomic_store_n(&gBadResult, 1, __ATOMIC_RELAXED);
  }
}

typedef struct {
  pthread_barrier_t *barrier;
  int kind;
} WorkerArg;

enum {
  kKindDirectScore = 1,
  kKindObjCScore,
  kKindLossless,
  kKindSemantic,
  kKindPatchMake
};

static NSMutableArray *SurroundedInsertion(void) {
  return [NSMutableArray arrayWithObjects:
    [Diff diffWithOperation:DIFF_EQUAL andText:@"hello world\n\n"],
    [Diff diffWithOperation:DIFF_INSERT andText:@"Q"],
    [Diff diffWithOperation:DIFF_EQUAL andText:@"tail"],
    nil];
}

static void *Worker(void *raw) {
  WorkerArg *arg = raw;
  /* GNU libobjc does not know pthread_create threads until they are registered. */
  GSRegisterCurrentThread();
  pthread_barrier_wait(arg->barrier);
  @autoreleasepool {
    switch (arg->kind) {
      case kKindDirectScore: {
        CFStringRef one = CFStringCreateWithCString(NULL, "alpha\n\n", kCFStringEncodingASCII);
        CFStringRef two = CFStringCreateWithCString(NULL, "\n\nbeta", kCFStringEncodingASCII);
        ExpectScore(diff_cleanupSemanticScore(one, two), 5);
        CFRelease(one);
        CFRelease(two);
        break;
      }
      case kKindObjCScore: {
        DiffMatchPatch *dmp = [[DiffMatchPatch alloc] init];
        NSInteger score = [dmp diff_cleanupSemanticScoreOfFirstString:@"alpha\n\n" andSecondString:@"\n\nbeta"];
        ExpectScore((CFIndex)score, 5);
        break;
      }
      case kKindLossless: {
        DiffMatchPatch *dmp = [[DiffMatchPatch alloc] init];
        [dmp diff_cleanupSemanticLossless:SurroundedInsertion()];
        break;
      }
      case kKindSemantic: {
        DiffMatchPatch *dmp = [[DiffMatchPatch alloc] init];
        [dmp diff_cleanupSemantic:SurroundedInsertion()];
        break;
      }
      case kKindPatchMake: {
        char prefix[96];
        char suffix[96];
        memset(prefix, 'p', 80);
        prefix[80] = '\n';
        prefix[81] = '\n';
        prefix[82] = '\0';
        memset(suffix, 's', 80);
        suffix[80] = '\0';
        char oldText[256];
        char newText[256];
        snprintf(oldText, sizeof oldText, "%s%s", prefix, suffix);
        snprintf(newText, sizeof newText, "%sQ%s", prefix, suffix);
        DiffMatchPatch *dmp = [[DiffMatchPatch alloc] init];
        NSMutableArray *patches = [dmp patch_makeFromOldString:CFString(oldText) andNewString:CFString(newText)];
        if (patches.count == 0) {
          __atomic_store_n(&gBadResult, 1, __ATOMIC_RELAXED);
        }
        break;
      }
    }
  }
  GSUnregisterCurrentThread();
  return NULL;
}

static int RunRace(int kind) {
  WarmCharacterSets();
  (void)GSCurrentThread();
  pthread_barrier_t barrier;
  pthread_barrier_init(&barrier, NULL, kThreads);
  pthread_t threads[kThreads];
  WorkerArg arg = { .barrier = &barrier, .kind = kind };
  for (int i = 0; i < kThreads; i++) {
    pthread_create(&threads[i], NULL, Worker, &arg);
  }
  for (int i = 0; i < kThreads; i++) {
    pthread_join(threads[i], NULL);
  }
  pthread_barrier_destroy(&barrier);

  @autoreleasepool {
    CFStringRef one = CFStringCreateWithCString(NULL, "alpha\n\n", kCFStringEncodingASCII);
    CFStringRef two = CFStringCreateWithCString(NULL, "\n\nbeta", kCFStringEncodingASCII);
    CFStringRef word1 = CFStringCreateWithCString(NULL, "ab", kCFStringEncodingASCII);
    CFStringRef word2 = CFStringCreateWithCString(NULL, "cd", kCFStringEncodingASCII);
    ExpectScore(diff_cleanupSemanticScore(one, two), 5);
    ExpectScore(diff_cleanupSemanticScore(word1, word2), 0);
    CFRelease(one);
    CFRelease(two);
    CFRelease(word1);
    CFRelease(word2);
  }
  return ChildStatus();
}

static int Fail(const char *name, int status, int signalNumber) {
  if (signalNumber != 0) {
    fprintf(stderr, "FAIL %s: crashed with signal %d\n", name, signalNumber);
  } else if (status == kExitRace) {
    fprintf(stderr, "FAIL %s: overlapping regcomp or regexec during regcomp\n", name);
  } else if (status == kExitNoRegcomp) {
    fprintf(stderr, "FAIL %s: semantic cleanup did not compile the regexes\n", name);
  } else if (status == kExitNoRegexec) {
    fprintf(stderr, "FAIL %s: blank-line score did not call regexec\n", name);
  } else if (status == kExitBadResult) {
    fprintf(stderr, "FAIL %s: cleanup result was wrong\n", name);
  } else {
    fprintf(stderr, "FAIL %s: status %d\n", name, status);
  }
  return 1;
}

static int Check(const char *name, int kind) {
  pid_t pid = fork();
  if (pid < 0) {
    perror("fork");
    return 1;
  }
  if (pid == 0) {
    int status = 0;
    @autoreleasepool {
      status = RunRace(kind);
    }
    _exit(status);
  }
  int waitStatus = 0;
  if (waitpid(pid, &waitStatus, 0) < 0) {
    perror("waitpid");
    return 1;
  }
  if (WIFSIGNALED(waitStatus)) {
    return Fail(name, 0, WTERMSIG(waitStatus));
  }
  if (!WIFEXITED(waitStatus) || WEXITSTATUS(waitStatus) != 0) {
    int code = WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : -1;
    return Fail(name, code, 0);
  }
  printf("PASS %s\n", name);
  return 0;
}

int main(void) {
  int failed = 0;
  failed |= Check("direct_semantic_score", kKindDirectScore);
  failed |= Check("objc_semantic_score", kKindObjCScore);
  failed |= Check("cleanup_semantic_lossless", kKindLossless);
  failed |= Check("cleanup_semantic", kKindSemantic);
  failed |= Check("patch_make_from_texts", kKindPatchMake);
  return failed ? 1 : 0;
}
