#!/usr/bin/env python3
"""
DSH Web — Native Linux Desktop Client for DeepSeek Harness Web UI
Supports GTK3 + WebKit2GTK with mode selection (KeepAlive via systemd vs Normal Mode)
"""

import os
import sys
import json
import signal
import socket
import subprocess
import fcntl
from pathlib import Path

HOME = str(Path.home())
DEFAULT_PORT = 3080
HOST = "127.0.0.1"

CONFIG_DIR = os.path.join(HOME, ".config", "dsh-web")
DATA_DIR = os.path.join(HOME, ".local", "share", "dsh-web")
LOG_DIR = os.path.join(DATA_DIR, "logs")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")
LOCK_FILE = os.path.join(DATA_DIR, "launcher.lock")
SYSTEMD_USER_DIR = os.path.join(HOME, ".config", "systemd", "user")
SYSTEMD_SERVICE_FILE = os.path.join(SYSTEMD_USER_DIR, "dsh-web.service")

os.makedirs(CONFIG_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)
os.makedirs(LOG_DIR, exist_ok=True)

def read_config():
    if os.path.isfile(CONFIG_FILE):
        try:
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {"keepAlive": True, "port": DEFAULT_PORT, "dshPath": None, "nodePath": None}

def save_config(cfg):
    try:
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
    except Exception as e:
        print(f"Failed to save config: {e}", file=sys.stderr)

def get_candidate_paths():
    paths = [
        os.path.join(HOME, ".local", "bin"),
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        os.path.join(HOME, ".fnm", "current", "bin"),
        os.path.join(HOME, ".volta", "bin"),
        os.path.join(HOME, ".asdf", "shims"),
        os.path.join(HOME, ".pnpm-global", "bin"),
        os.path.join(HOME, ".bun", "bin"),
        os.path.join(HOME, ".yarn", "bin"),
    ]
    # NVM
    nvm_base = os.path.join(HOME, ".nvm", "versions", "node")
    if os.path.isdir(nvm_base):
        try:
            for ver in sorted(os.listdir(nvm_base), reverse=True):
                paths.insert(0, os.path.join(nvm_base, ver, "bin"))
        except Exception:
            pass
    
    current_path = os.environ.get("PATH", "")
    for p in current_path.split(":"):
        if p and p not in paths:
            paths.append(p)
    return paths

def find_executable(name, override_path=None):
    if override_path and os.path.isfile(override_path) and os.access(override_path, os.X_OK):
        return override_path
    
    env_key = f"{name.upper().replace('-', '_')}_BIN"
    if env_key in os.environ and os.path.isfile(os.environ[env_key]):
        return os.environ[env_key]

    for p in get_candidate_paths():
        full = os.path.join(p, name)
        if os.path.isfile(full) and os.access(full, os.X_OK):
            return full
    return None

def resolve_backend_command(cfg):
    port = cfg.get("port", DEFAULT_PORT)
    
    # 1. dsh binary
    dsh_bin = find_executable("dsh", cfg.get("dshPath"))
    if dsh_bin:
        return [dsh_bin, "web", "--port", str(port)]
    
    # 2. node + bin.js
    node_bin = find_executable("node", cfg.get("nodePath"))
    if node_bin:
        candidate_scripts = [
            os.path.join(HOME, ".local", "lib", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js"),
            "/usr/local/lib/node_modules/@deepseek-ai/dsh/lib/bin.js",
            "/usr/lib/node_modules/@deepseek-ai/dsh/lib/bin.js",
            os.path.join(HOME, ".config", "yarn", "global", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js"),
        ]
        for s in candidate_scripts:
            if os.path.isfile(s):
                return [node_bin, s, "web", "--port", str(port)]
    
    return None

def is_port_in_use(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1.0)
        return s.connect_ex((HOST, port)) == 0

def configure_systemd_service(enable, cfg):
    if enable:
        cmd = resolve_backend_command(cfg)
        if not cmd:
            return False
        exec_start = " ".join(cmd)
        path_str = ":".join(get_candidate_paths())
        log_file = os.path.join(LOG_DIR, "dsh-web.log")
        
        service_content = f"""[Unit]
Description=DeepSeek Harness Web Backend Daemon
After=network.target

[Service]
Type=simple
ExecStart={exec_start}
Restart=always
RestartSec=5
WorkingDirectory={HOME}
Environment="PATH={path_str}"
Environment="NO_PROXY=localhost,127.0.0.1"
Environment="no_proxy=localhost,127.0.0.1"
StandardOutput=append:{log_file}
StandardError=append:{log_file}

[Install]
WantedBy=default.target
"""
        os.makedirs(SYSTEMD_USER_DIR, exist_ok=True)
        with open(SYSTEMD_SERVICE_FILE, "w", encoding="utf-8") as f:
            f.write(service_content)
        
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
        subprocess.run(["systemctl", "--user", "enable", "--now", "dsh-web.service"], check=False)
    else:
        subprocess.run(["systemctl", "--user", "stop", "dsh-web.service"], check=False)
        subprocess.run(["systemctl", "--user", "disable", "dsh-web.service"], check=False)
        if os.path.exists(SYSTEMD_SERVICE_FILE):
            try:
                os.remove(SYSTEMD_SERVICE_FILE)
            except Exception:
                pass
        subprocess.run(["systemctl", "--user", "daemon-reload"], check=False)
    return True

# GTK + WebKit UI
def run_gui():
    import gi
    try:
        gi.require_version("Gtk", "3.0")
        try:
            gi.require_version("WebKit2", "4.1")
        except ValueError:
            gi.require_version("WebKit2", "4.0")
        from gi.repository import Gtk, WebKit2, GLib, Gdk
    except Exception as e:
        print(f"Error loading GTK/WebKit2: {e}", file=sys.stderr)
        print("Please install libwebkit2gtk (e.g. `sudo apt install gir1.2-webkit2-4.1` on Ubuntu/Debian)")
        # Fallback to opening default browser
        cfg = read_config()
        port = cfg.get("port", DEFAULT_PORT)
        url = f"http://{HOST}:{port}"
        print(f"Opening {url} in browser...")
        subprocess.run(["xdg-open", url], check=False)
        return

    config = read_config()
    port = config.get("port", DEFAULT_PORT)
    web_url = f"http://{HOST}:{port}"
    backend_proc = None

    # Single instance lock
    lock_fd = os.open(LOCK_FILE, os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("DSH Web is already running.")
        sys.exit(0)

    win = Gtk.Window(title="DeepSeek Harness")
    win.set_default_size(1280, 850)
    win.set_position(Gtk.WindowPosition.CENTER)

    # Icon lookup
    for icon_name in ["dsh-web", "deepseek-harness"]:
        if Gtk.IconTheme.get_default().has_icon(icon_name):
            win.set_icon_name(icon_name)
            break

    # HeaderBar
    hb = Gtk.HeaderBar()
    hb.set_show_close_button(True)
    hb.set_title("DeepSeek Harness")
    win.set_titlebar(hb)

    # Reload Button
    reload_btn = Gtk.Button.new_from_icon_name("view-refresh-symbolic", Gtk.IconSize.BUTTON)
    reload_btn.set_tooltip_text("刷新页面")
    hb.pack_start(reload_btn)

    # Mode Menu Button
    mode_btn = Gtk.MenuButton()
    mode_btn.set_label("运行模式")
    mode_menu = Gtk.Menu()

    keepalive_item = Gtk.RadioMenuItem(label="常驻模式")
    normal_item = Gtk.RadioMenuItem.new_from_widget(keepalive_item)
    normal_item.set_label("随窗模式")

    if config.get("keepAlive", True):
        keepalive_item.set_active(True)
    else:
        normal_item.set_active(True)

    mode_menu.append(keepalive_item)
    mode_menu.append(normal_item)
    mode_menu.show_all()
    mode_btn.set_popup(mode_menu)
    hb.pack_end(mode_btn)

    # WebKit View
    webview = WebKit2.WebView()
    win.add(webview)

    def on_reload_clicked(btn):
        webview.reload()
    reload_btn.connect("clicked", on_reload_clicked)

    def show_alert(title, text):
        dialog = Gtk.MessageDialog(
            transient_for=win,
            flags=0,
            message_type=Gtk.MessageType.INFO,
            buttons=Gtk.ButtonsType.OK,
            text=title,
        )
        dialog.format_secondary_text(text)
        dialog.run()
        dialog.destroy()

    def on_keepalive_toggled(item):
        if item.get_active():
            config["keepAlive"] = True
            save_config(config)
            configure_systemd_service(True, config)
            show_alert("已切换为：常驻模式", "系统已启用常驻守护：\n- 后台服务异常退出时 5 秒内自动重启。\n- 关闭界面不中断后台任务。")

    def on_normal_toggled(item):
        if item.get_active():
            config["keepAlive"] = False
            save_config(config)
            configure_systemd_service(False, config)
            show_alert("已切换为：随窗模式", "已移除常驻守护：\n- 关闭窗口时将停止后台服务并释放端口。")

    keepalive_item.connect("toggled", on_keepalive_toggled)
    normal_item.connect("toggled", on_normal_toggled)

    def poll_and_load():
        if is_port_in_use(port):
            webview.load_uri(web_url)
            return False  # stop GLib timeout
        return True  # repeat

    def spawn_backend():
        nonlocal backend_proc
        cmd = resolve_backend_command(config)
        if not cmd:
            dialog = Gtk.MessageDialog(
                transient_for=win,
                flags=0,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.CLOSE,
                text="未检测到 DeepSeek Harness 或 Node.js",
            )
            dialog.format_secondary_text("请先在终端安装：\n  npm install -g @deepseek-ai/dsh\n\n安装完成后重新启动本应用。")
            dialog.run()
            dialog.destroy()
            sys.exit(1)
        
        env = os.environ.copy()
        env["PATH"] = ":".join(get_candidate_paths())
        backend_proc = subprocess.Popen(
            cmd,
            cwd=HOME,
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        GLib.timeout_add(500, poll_and_load)

    # Start logic
    if config.get("keepAlive", True):
        configure_systemd_service(True, config)
        GLib.timeout_add(500, poll_and_load)
    else:
        if is_port_in_use(port):
            webview.load_uri(web_url)
        else:
            spawn_backend()

    def on_destroy(w):
        if not config.get("keepAlive", True) and backend_proc:
            try:
                backend_proc.terminate()
                backend_proc.wait(timeout=2)
            except Exception:
                backend_proc.kill()
        Gtk.main_quit()

    win.connect("destroy", on_destroy)
    win.show_all()
    Gtk.main()

if __name__ == "__main__":
    run_gui()
