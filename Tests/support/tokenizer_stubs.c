#include <stdio.h>
#include <stdlib.h>

#include "tokenizer_compat.h"

CFStringTokenizerRef CFStringTokenizerCreate(CFAllocatorRef alloc, CFStringRef string, CFRange range, CFOptionFlags options, CFLocaleRef locale) {
  (void)alloc;
  (void)string;
  (void)range;
  (void)options;
  (void)locale;
  fprintf(stderr, "CFStringTokenizerCreate was not expected on the semantic-cleanup path\n");
  abort();
}

CFStringTokenizerTokenType CFStringTokenizerGoToTokenAtIndex(CFStringTokenizerRef tokenizer, CFIndex index) {
  (void)tokenizer;
  (void)index;
  abort();
}

CFRange CFStringTokenizerGetCurrentTokenRange(CFStringTokenizerRef tokenizer) {
  (void)tokenizer;
  abort();
}

CFStringTokenizerTokenType CFStringTokenizerAdvanceToNextToken(CFStringTokenizerRef tokenizer) {
  (void)tokenizer;
  abort();
}
