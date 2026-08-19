/*
 * DSH Web — Native Linux C Desktop Client using GTK3 & WebKit2GTK
 */

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/file.h>
#include <sys/stat.h>

#define DEFAULT_PORT 3080
#define DEFAULT_HOST "127.0.0.1"

static WebKitWebView *web_view = NULL;
static GtkWidget *window = NULL;
static GPid backend_pid = 0;
static gboolean keep_alive_mode = TRUE;

static void on_reload_clicked(GtkButton *btn, gpointer user_data) {
    if (web_view) {
        webkit_web_view_reload(web_view);
    }
}

static void on_window_destroy(GtkWidget *widget, gpointer user_data) {
    if (!keep_alive_mode && backend_pid > 0) {
        kill(backend_pid, SIGTERM);
    }
    gtk_main_quit();
}

int main(int argc, char *argv[]) {
    gtk_init(&argc, &argv);

    char *home = getenv("HOME");
    if (!home) home = "/tmp";

    char lock_path[512];
    snprintf(lock_path, sizeof(lock_path), "%s/.local/share/dsh-web/launcher.lock", home);
    
    char dir_path[512];
    snprintf(dir_path, sizeof(dir_path), "%s/.local/share/dsh-web", home);
    mkdir(dir_path, 0755);

    int lock_fd = open(lock_path, O_CREAT | O_RDWR, 0644);
    if (lock_fd >= 0) {
        if (flock(lock_fd, LOCK_EX | LOCK_NB) != 0) {
            fprintf(stderr, "DSH Web is already running.\n");
            return 0;
        }
    }

    window = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    gtk_window_set_title(GTK_WINDOW(window), "DeepSeek Harness");
    gtk_window_set_default_size(GTK_WINDOW(window), 1280, 850);
    gtk_window_set_position(GTK_WINDOW(window), GTK_WIN_POS_CENTER);

    GtkHeaderBar *header = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_header_bar_set_show_close_button(header, TRUE);
    gtk_header_bar_set_title(header, "DeepSeek Harness");
    gtk_window_set_titlebar(GTK_WINDOW(window), GTK_WIDGET(header));

    GtkWidget *reload_btn = gtk_button_new_from_icon_name("view-refresh-symbolic", GTK_ICON_SIZE_BUTTON);
    gtk_widget_set_tooltip_text(reload_btn, "刷新页面");
    g_signal_connect(reload_btn, "clicked", G_CALLBACK(on_reload_clicked), NULL);
    gtk_header_bar_pack_start(header, reload_btn);

    web_view = WEBKIT_WEB_VIEW(webkit_web_view_new());
    gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(web_view));

    char url[64];
    snprintf(url, sizeof(url), "http://%s:%d", DEFAULT_HOST, DEFAULT_PORT);
    webkit_web_view_load_uri(web_view, url);

    g_signal_connect(window, "destroy", G_CALLBACK(on_window_destroy), NULL);

    gtk_widget_show_all(window);
    gtk_main();

    return 0;
}
