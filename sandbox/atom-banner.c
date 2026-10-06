/* A small X client so the desktop is obviously Atom even when a terminal
 * cannot allocate a pty. Linked against libX11, which Xvfb already needs.
 */
#include <X11/Xlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
    Display *display = XOpenDisplay(NULL);
    if (!display) {
        fprintf(stderr, "atom-banner: cannot open display\n");
        return 1;
    }

    int screen = DefaultScreen(display);
    Window window = XCreateSimpleWindow(
        display, RootWindow(display, screen),
        80, 80, 720, 280, 2,
        BlackPixel(display, screen), WhitePixel(display, screen));
    XStoreName(display, window, "Atom desktop");
    XSelectInput(display, window, ExposureMask);
    XMapWindow(display, window);

    GC gc = XCreateGC(display, window, 0, NULL);
    XSetForeground(display, gc, BlackPixel(display, screen));
    const char *line1 = "Atom desktop";
    const char *line2 = "OpenShell sandbox  DISPLAY=:0  view-only noVNC";

    for (;;) {
        XEvent event;
        XNextEvent(display, &event);
        if (event.type == Expose) {
            XDrawString(display, window, gc, 40, 120, line1, (int)strlen(line1));
            XDrawString(display, window, gc, 40, 160, line2, (int)strlen(line2));
        }
    }

    return 0;
}
