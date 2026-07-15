/*
 * backend-mali-fbdev.c — WPE backend mínimo para Mali fbdev (muOS/RG40xx H)
 * C PURO com funções nomeadas → vtables ficam em .data.rel.ro (const), NÃO em BSS.
 * Single-process, sem IPC, sem X/Wayland/DRM. Baseado no viv-imx6 do WPEBackend-rdk.
 *
 * CHAVE (validado por spike egltest.c no device):
 *   - get_native_display -> EGL_DEFAULT_DISPLAY
 *   - get_native_window  -> (EGLNativeWindowType)0   [mali fbdev dá fullscreen com NULL]
 *   - single-process: get_renderer_host_fd -> -1 (sem host IPC)
 * API: libwpe 1.14 (Debian bookworm arm64).
 */
#include <wpe/wpe.h>
#include <wpe/wpe-egl.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

/* ======================= VIEW BACKEND ======================= */
struct ViewBackend {
    struct wpe_view_backend* backend;
    uint32_t width;
    uint32_t height;
};

static void* vb_create(void* p, struct wpe_view_backend* backend)
{
    (void)p;
    struct ViewBackend* vb = (struct ViewBackend*)malloc(sizeof(struct ViewBackend));
    vb->backend = backend;
    const char* w = getenv("WPE_FBDEV_WIDTH");
    const char* h = getenv("WPE_FBDEV_HEIGHT");
    vb->width  = w ? (uint32_t)atoi(w) : 640;
    vb->height = h ? (uint32_t)atoi(h) : 480;
    fprintf(stderr, "[mali-fbdev] view_backend create %ux%u\n", vb->width, vb->height);
    return vb;
}
static void vb_destroy(void* data) { free(data); }
static void vb_initialize(void* data)
{
    struct ViewBackend* vb = (struct ViewBackend*)data;
    fprintf(stderr, "[mali-fbdev] view_backend initialize -> set_size %ux%u\n", vb->width, vb->height);
    wpe_view_backend_dispatch_set_size(vb->backend, vb->width, vb->height);
}
static int vb_get_renderer_host_fd(void* data) { (void)data; return -1; }

struct wpe_view_backend_interface mali_fbdev_view_backend_interface = {
    vb_create,
    vb_destroy,
    vb_initialize,
    vb_get_renderer_host_fd,
    NULL, NULL, NULL, NULL
};

/* ======================= RENDERER BACKEND EGL ======================= */
static void* reb_create(int fd) { (void)fd; return NULL; }
static void  reb_destroy(void* data) { (void)data; }
static EGLNativeDisplayType reb_get_native_display(void* data)
{
    (void)data;
    fprintf(stderr, "[mali-fbdev] get_native_display -> EGL_DEFAULT_DISPLAY\n");
    return EGL_DEFAULT_DISPLAY;
}
static uint32_t reb_get_platform(void* data) { (void)data; return 0; }

struct wpe_renderer_backend_egl_interface mali_fbdev_renderer_backend_egl_interface = {
    reb_create,
    reb_destroy,
    reb_get_native_display,
    reb_get_platform,
    NULL, NULL, NULL
};

/* ======================= RENDERER BACKEND EGL TARGET ======================= */
/* mali fbdev native window (ABI do libmali fbdev winsys) */
struct fbdev_window {
    unsigned short width;
    unsigned short height;
};

struct EGLTarget {
    struct wpe_renderer_backend_egl_target* target;
    uint32_t width;
    uint32_t height;
    struct fbdev_window* win;
};

static void* tgt_create(struct wpe_renderer_backend_egl_target* target, int host_fd)
{
    (void)host_fd;
    struct EGLTarget* t = (struct EGLTarget*)malloc(sizeof(struct EGLTarget));
    t->target = target;
    t->width = 640;
    t->height = 480;
    t->win = NULL;
    fprintf(stderr, "[mali-fbdev] TARGET create\n");
    return t;
}
static void tgt_destroy(void* data) { free(data); }
static void tgt_initialize(void* data, void* backend, uint32_t width, uint32_t height)
{
    (void)backend;
    struct EGLTarget* t = (struct EGLTarget*)data;
    t->width = width;
    t->height = height;
    fprintf(stderr, "[mali-fbdev] TARGET initialize %ux%u\n", width, height);
}
static EGLNativeWindowType tgt_get_native_window(void* data)
{
    struct EGLTarget* t = (struct EGLTarget*)data;
    /* mali fbdev espera um struct fbdev_window{u16 width,height} real.
     * Com NULL alguns builds criam surface dummy (compositor pinta em FBO e nao apresenta).
     * Alocamos e mantemos vivo pelo tempo do target. */
    if (!t->win) {
        t->win = (struct fbdev_window*)malloc(sizeof(struct fbdev_window));
        t->win->width  = (unsigned short)t->width;
        t->win->height = (unsigned short)t->height;
    }
    fprintf(stderr, "[mali-fbdev] get_native_window -> fbdev_window %ux%u\n", t->win->width, t->win->height);
    return (EGLNativeWindowType)t->win;
}
static void tgt_resize(void* data, uint32_t w, uint32_t h)
{
    struct EGLTarget* t = (struct EGLTarget*)data;
    t->width = w; t->height = h;
    if (t->win) { t->win->width = (unsigned short)w; t->win->height = (unsigned short)h; }
    fprintf(stderr, "[mali-fbdev] TARGET resize %ux%u\n", w, h);
}
static void tgt_frame_will_render(void* data)
{
    struct EGLTarget* t = (struct EGLTarget*)data;
    static unsigned long fwr = 0;
    ++fwr;
    /* LOG SILENCIADO: o fprintf por frame floodava o tee->SD (~3fps de I/O sincrono).
     * Reativar so p/ debug via MUOS_FRAME_LOG=1. */
    if (getenv("MUOS_FRAME_LOG") && (fwr <= 8 || (fwr % 300) == 0))
        fprintf(stderr, "[mali-fbdev] frame_will_render #%lu -> dispatch_frame_complete\n", fwr);
    /* WebKit neste build NAO chama frame_rendered apos o swap, entao o WPE bloqueia
     * esperando o frame_complete (throttle) apos ~4 frames -> congela tick/timers/JS.
     * Como somos single-process fbdev sem compositor real, sinalizamos o complete
     * proativamente aqui (o eglSwapBuffers ja aconteceu no compositor do WebProcess). */
    wpe_renderer_backend_egl_target_dispatch_frame_complete(t->target);
}
static void tgt_frame_rendered(void* data)
{
    struct EGLTarget* t = (struct EGLTarget*)data;
    static unsigned long fr = 0;
    ++fr;
    if (getenv("MUOS_FRAME_LOG") && (fr <= 8 || (fr % 300) == 0))
        fprintf(stderr, "[mali-fbdev] frame_rendered #%lu\n", fr);
    /* frame_complete ja foi disparado em frame_will_render; nao duplicar. */
    (void)t;
}
static void tgt_deinitialize(void* data) { (void)data; }

struct wpe_renderer_backend_egl_target_interface mali_fbdev_renderer_backend_egl_target_interface = {
    tgt_create,
    tgt_destroy,
    tgt_initialize,
    tgt_get_native_window,
    tgt_resize,
    tgt_frame_will_render,
    tgt_frame_rendered,
    tgt_deinitialize,
    NULL, NULL, NULL
};

/* ======================= OFFSCREEN TARGET ======================= */
struct OffscreenTarget {
    struct fbdev_window* win;
};

static void* off_create(void)
{
    struct OffscreenTarget* o = (struct OffscreenTarget*)malloc(sizeof(struct OffscreenTarget));
    o->win = NULL;
    fprintf(stderr, "[mali-fbdev] OFFSCREEN create\n");
    return o;
}
static void off_destroy(void* data)
{
    struct OffscreenTarget* o = (struct OffscreenTarget*)data;
    if (o) free(o->win);
    free(o);
}
static void off_initialize(void* data, void* backend)
{
    (void)backend;
    struct OffscreenTarget* o = (struct OffscreenTarget*)data;
    if (!o->win) {
        o->win = (struct fbdev_window*)malloc(sizeof(struct fbdev_window));
        /* Surface pequena mas válida para contextos auxiliares/WebGL sharing. */
        o->win->width = 640;
        o->win->height = 480;
    }
    fprintf(stderr, "[mali-fbdev] OFFSCREEN initialize window %ux%u\n", o->win->width, o->win->height);
}
static EGLNativeWindowType off_get_native_window(void* data)
{
    struct OffscreenTarget* o = (struct OffscreenTarget*)data;
    if (!o->win) {
        o->win = (struct fbdev_window*)malloc(sizeof(struct fbdev_window));
        o->win->width = 640;
        o->win->height = 480;
    }
    fprintf(stderr, "[mali-fbdev] OFFSCREEN get_native_window -> %ux%u\n", o->win->width, o->win->height);
    return (EGLNativeWindowType)o->win;
}

struct wpe_renderer_backend_egl_offscreen_target_interface mali_fbdev_renderer_backend_egl_offscreen_target_interface = {
    off_create,
    off_destroy,
    off_initialize,
    off_get_native_window
};

/* ======================= RENDERER HOST (no-op, single-process) ======================= */
static void* host_create(void) { return NULL; }
static void  host_destroy(void* data) { (void)data; }
static int   host_create_client(void* data) { (void)data; return -1; }

struct wpe_renderer_host_interface mali_fbdev_noop_renderer_host_interface = {
    host_create,
    host_destroy,
    host_create_client,
    NULL, NULL, NULL, NULL
};
