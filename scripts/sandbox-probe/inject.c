// Loaded with DYLD_INSERT_LIBRARIES by scripts/sandbox-probe.sh. If it runs, code injection worked.
#include <stdio.h>
__attribute__((constructor)) static void injected(void) { printf("ALLOWED\tcode injection: an injected library ran inside the process\n"); }
