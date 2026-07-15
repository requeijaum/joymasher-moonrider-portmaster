/* libgl-stub.c — libGL.so.1 mínima para satisfazer o NEEDED do libepoxy
 * SEM puxar o gl4es (que não exporta glXGetCurrentContext e faz o epoxy
 * abortar a init). Todos os símbolos GLX retornam NULL/0 → o libepoxy
 * conclui "nenhum contexto GLX ativo" e usa o caminho EGL (correto p/ fbdev/Mali).
 *
 * O backend mali-fbdev usa EGL + GLES diretamente (eglGetProcAddress), então
 * nenhuma função desktop-GL real é chamada em runtime.
 */
#include <stddef.h>

/* --- símbolos GLX que o libepoxy resolve na init --- */
void*         glXGetCurrentContext(void)      { return NULL; }
void*         glXGetCurrentDisplay(void)      { return NULL; }
unsigned long glXGetCurrentDrawable(void)     { return 0; }
unsigned long glXGetCurrentReadDrawable(void) { return 0; }
void*         glXGetProcAddress(const char *n){ (void)n; return NULL; }
void*         glXGetProcAddressARB(const char *n){ (void)n; return NULL; }
int           glXMakeCurrent(void *d, unsigned long w, void *c){ (void)d;(void)w;(void)c; return 0; }
int           glXMakeContextCurrent(void *d, unsigned long a, unsigned long b, void *c){ (void)d;(void)a;(void)b;(void)c; return 0; }
void*         glXCreateContext(void){ return NULL; }
void          glXDestroyContext(void *c){ (void)c; }
void          glXSwapBuffers(void *d, unsigned long w){ (void)d;(void)w; }
int           glXQueryVersion(void *d, int *maj, int *min){ (void)d; if(maj)*maj=1; if(min)*min=4; return 1; }
int           glXQueryExtension(void *d, int *a, int *b){ (void)d;(void)a;(void)b; return 0; }
const char*   glXQueryExtensionsString(void *d, int s){ (void)d;(void)s; return ""; }
const char*   glXGetClientString(void *d, int n){ (void)d;(void)n; return ""; }
const char*   glXQueryServerString(void *d, int s, int n){ (void)d;(void)s;(void)n; return ""; }
void          glXWaitGL(void){ }
void          glXWaitX(void){ }
void          glXSwapIntervalEXT(void *d, unsigned long w, int i){ (void)d;(void)w;(void)i; }
int           glXSwapIntervalMESA(unsigned int i){ (void)i; return 0; }
int           glXSwapIntervalSGI(int i){ (void)i; return 0; }
