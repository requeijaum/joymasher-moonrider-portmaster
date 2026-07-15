/*
 * loader-impl.c — entrypoint do wpebackend-mali-fbdev (C puro, sem lambdas).
 * Garante que _wpe_loader_interface fique em .data.rel.ro com load_object
 * inicializado estaticamente (ponteiro de função nomeada), NÃO em BSS.
 */
#include <wpe/wpe.h>
#include <string.h>

/* vtables definidas em backend-mali-fbdev.c */
extern struct wpe_view_backend_interface mali_fbdev_view_backend_interface;
extern struct wpe_renderer_backend_egl_interface mali_fbdev_renderer_backend_egl_interface;
extern struct wpe_renderer_backend_egl_target_interface mali_fbdev_renderer_backend_egl_target_interface;
extern struct wpe_renderer_backend_egl_offscreen_target_interface mali_fbdev_renderer_backend_egl_offscreen_target_interface;
extern struct wpe_renderer_host_interface mali_fbdev_noop_renderer_host_interface;

static void* mali_fbdev_load_object(const char* object_name)
{
    if (!strcmp(object_name, "_wpe_renderer_host_interface"))
        return &mali_fbdev_noop_renderer_host_interface;
    if (!strcmp(object_name, "_wpe_view_backend_interface"))
        return &mali_fbdev_view_backend_interface;
    if (!strcmp(object_name, "_wpe_renderer_backend_egl_interface"))
        return &mali_fbdev_renderer_backend_egl_interface;
    if (!strcmp(object_name, "_wpe_renderer_backend_egl_target_interface"))
        return &mali_fbdev_renderer_backend_egl_target_interface;
    if (!strcmp(object_name, "_wpe_renderer_backend_egl_offscreen_target_interface"))
        return &mali_fbdev_renderer_backend_egl_offscreen_target_interface;
    return 0;
}

__attribute__((visibility("default")))
struct wpe_loader_interface _wpe_loader_interface = {
    mali_fbdev_load_object,
    0, 0, 0, 0
};
