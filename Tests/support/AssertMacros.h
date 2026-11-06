/*
 * Test-build stand-in for the Apple SDK header DiffMatchPatchCFUtilities.c
 * includes. Production builds compile __Check_String out. The semantic-score
 * path does not use that macro.
 */
#ifndef __ASSERTMACROS__
#define __ASSERTMACROS__

#ifndef DEBUG_ASSERT_PRODUCTION_CODE
#define DEBUG_ASSERT_PRODUCTION_CODE 1
#endif

#ifndef __Check_String
#define __Check_String(assertion, message) \
  do { (void)(assertion); (void)(message); } while (0)
#endif

#endif
