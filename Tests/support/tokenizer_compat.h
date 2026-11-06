/*
 * GNUstep CoreBase does not ship CFStringTokenizer. The semantic-cleanup
 * race does not call it. These declarations let the translation unit compile;
 * the test provides aborting definitions so a stray call cannot pass silently.
 */
#ifndef TOKENIZER_COMPAT_H
#define TOKENIZER_COMPAT_H

#include <CoreFoundation/CoreFoundation.h>

typedef struct __CFStringTokenizer *CFStringTokenizerRef;
typedef CFOptionFlags CFStringTokenizerTokenType;

enum {
  kCFStringTokenizerTokenNone = 0
};

#ifndef kCFStringTokenizerUnitWordBoundary
#define kCFStringTokenizerUnitWordBoundary ((CFOptionFlags)0)
#define kCFStringTokenizerUnitSentence ((CFOptionFlags)1)
#define kCFStringTokenizerUnitParagraph ((CFOptionFlags)2)
#define kCFStringTokenizerUnitLineBreak ((CFOptionFlags)3)
#endif

CFStringTokenizerRef CFStringTokenizerCreate(CFAllocatorRef alloc, CFStringRef string, CFRange range, CFOptionFlags options, CFLocaleRef locale);
CFStringTokenizerTokenType CFStringTokenizerGoToTokenAtIndex(CFStringTokenizerRef tokenizer, CFIndex index);
CFRange CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer);
CFStringTokenizerTokenType CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer);

#endif
