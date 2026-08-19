using System;
using System.IO;
using System.Net.Sockets;
using System.Diagnostics;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Drawing;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace DshWeb
{
    public class AppConfig
    {
        public bool KeepAlive { get; set; } = true;
        public int Port { get; set; } = 3080;
        public string? DshPath { get; set; }
        public string? NodePath { get; set; }
    }

    public class MainForm : Form
    {
        private readonly AppConfig _config;
        private readonly string _configPath;
        private readonly string _logDir;
        private readonly string _appDataDir;
        private WebView2? _webView;
        private Process? _dshProcess;
        private NotifyIcon? _trayIcon;
        private ToolStripMenuItem? _keepAliveMenuItem;
        private ToolStripMenuItem? _normalMenuItem;
        private bool _isExiting = false;
        private CancellationTokenSource? _watchdogCts;

        public MainForm(AppConfig config, string configPath, string appDataDir, string logDir)
        {
            _config = config;
            _configPath = configPath;
            _appDataDir = appDataDir;
            _logDir = logDir;

            InitializeComponent();
            InitializeBackendAndWeb();
        }

        private void InitializeComponent()
        {
            Text = "DeepSeek Harness";
            Width = 1360;
            Height = 880;
            StartPosition = FormStartPosition.CenterScreen;
            MinimumSize = new Size(800, 600);

            // Icon
            string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "assets", "icons", "dsh-web.ico");
            if (File.Exists(iconPath))
            {
                Icon = new Icon(iconPath);
            }

            // MenuStrip
            var menuStrip = new MenuStrip();

            var modeMenu = new ToolStripMenuItem("运行模式 (&M)");
            _keepAliveMenuItem = new ToolStripMenuItem("常驻模式", null, OnKeepAliveClicked) { Checked = _config.KeepAlive };
            _normalMenuItem = new ToolStripMenuItem("随窗模式", null, OnNormalClicked) { Checked = !_config.KeepAlive };
            modeMenu.DropDownItems.Add(_keepAliveMenuItem);
            modeMenu.DropDownItems.Add(_normalMenuItem);

            var viewMenu = new ToolStripMenuItem("视图 (&V)");
            var reloadItem = new ToolStripMenuItem("刷新页面 (&R)", null, (s, e) => _webView?.Reload()) { ShortcutKeys = Keys.Control | Keys.R };
            viewMenu.DropDownItems.Add(reloadItem);

            menuStrip.Items.Add(modeMenu);
            menuStrip.Items.Add(viewMenu);
            MainMenuStrip = menuStrip;
            Controls.Add(menuStrip);

            // WebView2
            _webView = new WebView2
            {
                Dock = DockStyle.Fill
            };
            Controls.Add(_webView);
            _webView.BringToFront();

            // Tray Icon
            _trayIcon = new NotifyIcon
            {
                Text = "DeepSeek Harness",
                Icon = Icon ?? SystemIcons.Application,
                Visible = true
            };
            var trayContextMenu = new ContextMenuStrip();
            trayContextMenu.Items.Add("打开窗口", null, (s, e) => RestoreWindow());
            trayContextMenu.Items.Add(new ToolStripSeparator());
            trayContextMenu.Items.Add("退出 DeepSeek Harness", null, (s, e) => ExitApplication());
            _trayIcon.ContextMenuStrip = trayContextMenu;
            _trayIcon.DoubleClick += (s, e) => RestoreWindow();

            FormClosing += OnFormClosing;
        }

        private void RestoreWindow()
        {
            Show();
            WindowState = FormWindowState.Normal;
            BringToFront();
            Activate();
        }

        private void ExitApplication()
        {
            _isExiting = true;
            _watchdogCts?.Cancel();
            if (!_config.KeepAlive && _dshProcess != null && !_dshProcess.HasExited)
            {
                try { _dshProcess.Kill(true); } catch { }
            }
            _trayIcon?.Dispose();
            Application.Exit();
        }

        private async void InitializeBackendAndWeb()
        {
            try
            {
                string userDataFolder = Path.Combine(_appDataDir, "WebView2Data");
                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                await _webView!.EnsureCoreWebView2Async(env);
            }
            catch (Exception ex)
            {
                MessageBox.Show($"WebView2 初始化失败: {ex.Message}\n请确保系统已安装 Microsoft Edge WebView2 Runtime。", "DeepSeek Harness", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            if (_config.KeepAlive)
            {
                StartBackendWithWatchdog();
                PollAndLoadWebUI();
            }
            else
            {
                if (!IsPortFree(_config.Port))
                {
                    PollAndLoadWebUI();
                }
                else
                {
                    SpawnBackendDirect();
                    PollAndLoadWebUI();
                }
            }
        }

        private void OnKeepAliveClicked(object? sender, EventArgs e)
        {
            _config.KeepAlive = true;
            _keepAliveMenuItem!.Checked = true;
            _normalMenuItem!.Checked = false;
            SaveConfig();
            StartBackendWithWatchdog();
            MessageBox.Show("已切换为：常驻模式\n\n- 后台服务异常退出时将自动重启。\n- 关闭窗口后后台服务与远程连接将保持 24/7 运行。\n- 可通过托盘图标随时唤出窗口。", "运行模式切换", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void OnNormalClicked(object? sender, EventArgs e)
        {
            _config.KeepAlive = false;
            _keepAliveMenuItem!.Checked = false;
            _normalMenuItem!.Checked = true;
            _watchdogCts?.Cancel();
            SaveConfig();
            MessageBox.Show("已切换为：随窗模式\n\n- 关闭窗口时将彻底停止后台服务并释放端口。", "运行模式切换", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }

        private void SaveConfig()
        {
            try
            {
                string json = JsonSerializer.Serialize(_config, new JsonSerializerOptions { WriteIndented = true });
                File.WriteAllText(_configPath, json);
            }
            catch { }
        }

        private static bool IsPortFree(int port)
        {
            try
            {
                using var client = new TcpClient();
                var result = client.BeginConnect("127.0.0.1", port, null, null);
                bool success = result.AsyncWaitHandle.WaitOne(TimeSpan.FromMilliseconds(500));
                if (!success) return true;
                client.EndConnect(result);
                return false;
            }
            catch
            {
                return true;
            }
        }

        private void PollAndLoadWebUI()
        {
            Task.Run(async () =>
            {
                string url = $"http://127.0.0.1:{_config.Port}";
                while (!_isExiting)
                {
                    if (!IsPortFree(_config.Port))
                    {
                        Invoke(() =>
                        {
                            if (_webView?.CoreWebView2 != null)
                            {
                                _webView.Source = new Uri(url);
                            }
                        });
                        break;
                    }
                    await Task.Delay(500);
                }
            });
        }

        private void StartBackendWithWatchdog()
        {
            _watchdogCts?.Cancel();
            _watchdogCts = new CancellationTokenSource();
            var token = _watchdogCts.Token;

            Task.Run(async () =>
            {
                while (!token.IsCancellationRequested && !_isExiting)
                {
                    if (IsPortFree(_config.Port))
                    {
                        SpawnBackendDirect();
                    }
                    await Task.Delay(5000, token);
                }
            }, token);
        }

        private void SpawnBackendDirect()
        {
            var (exe, args) = ResolveBackendCommand(_config);
            if (string.IsNullOrEmpty(exe))
            {
                Invoke(() =>
                {
                    MessageBox.Show("未检测到 DeepSeek Harness 或 Node.js\n\n请在终端中执行：\n  npm install -g @deepseek-ai/dsh\n\n安装完成后重新启动本应用。", "DeepSeek Harness", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                });
                return;
            }

            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = exe,
                    Arguments = args,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    WorkingDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile)
                };

                // Inject PATH
                string existingPath = Environment.GetEnvironmentVariable("PATH") ?? "";
                string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string extraPaths = $"{Path.Combine(appData, "npm")};{Path.Combine(localAppData, "Programs", "nodejs")};C:\\Program Files\\nodejs";
                psi.EnvironmentVariables["PATH"] = $"{extraPaths};{existingPath}";

                _dshProcess = Process.Start(psi);
            }
            catch (Exception ex)
            {
                File.AppendAllText(Path.Combine(_logDir, "launcher.log"), $"[{DateTime.Now}] Failed to spawn dsh: {ex.Message}\n");
            }
        }

        public static (string exe, string args) ResolveBackendCommand(AppConfig config)
        {
            int port = config.Port;

            // 1. Direct dsh command
            string? dsh = FindExecutable("dsh.cmd", config.DshPath) ?? FindExecutable("dsh.exe", config.DshPath) ?? FindExecutable("dsh", config.DshPath);
            if (!string.IsNullOrEmpty(dsh))
            {
                return (dsh, $"web --port {port}");
            }

            // 2. Node + bin.js
            string? node = FindExecutable("node.exe", config.NodePath) ?? FindExecutable("node", config.NodePath);
            if (!string.IsNullOrEmpty(node))
            {
                string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
                string candidate = Path.Combine(appData, "npm", "node_modules", "@deepseek-ai", "dsh", "lib", "bin.js");
                if (File.Exists(candidate))
                {
                    return (node, $"\"{candidate}\" web --port {port}");
                }
            }

            return ("", "");
        }

        private static string? FindExecutable(string name, string? overridePath)
        {
            if (!string.IsNullOrEmpty(overridePath) && File.Exists(overridePath)) return overridePath;

            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

            var candidates = new[]
            {
                Path.Combine(appData, "npm", name),
                Path.Combine(localAppData, "Programs", "nodejs", name),
                Path.Combine("C:\\Program Files\\nodejs", name),
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".local", "bin", name)
            };

            foreach (var c in candidates)
            {
                if (File.Exists(c)) return c;
            }

            string pathVar = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (var dir in pathVar.Split(';', StringSplitOptions.RemoveEmptyEntries))
            {
                string full = Path.Combine(dir.Trim(), name);
                if (File.Exists(full)) return full;
            }

            return null;
        }

        private void OnFormClosing(object? sender, FormClosingEventArgs e)
        {
            if (_isExiting) return;

            if (_config.KeepAlive)
            {
                e.Cancel = true;
                Hide();
                _trayIcon?.ShowBalloonTip(2000, "DeepSeek Harness", "应用已最小化到系统托盘，后台任务与远程服务保持常驻运行。", ToolTipIcon.Info);
            }
            else
            {
                ExitApplication();
            }
        }
    }

    internal static class Program
    {
        private static Mutex? _singleInstanceMutex;

        [STAThread]
        private static void Main()
        {
            const string mutexName = "Global\\ai.deepseek.dsh-web-desktop";
            _singleInstanceMutex = new Mutex(true, mutexName, out bool createdNew);
            if (!createdNew)
            {
                return;
            }

            ApplicationConfiguration.Initialize();

            string appData = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DSH Web");
            string logDir = Path.Combine(appData, "logs");
            string configPath = Path.Combine(appData, "config.json");

            Directory.CreateDirectory(appData);
            Directory.CreateDirectory(logDir);

            AppConfig config;
            if (File.Exists(configPath))
            {
                try
                {
                    string json = File.ReadAllText(configPath);
                    config = JsonSerializer.Deserialize<AppConfig>(json) ?? new AppConfig();
                }
                catch
                {
                    config = new AppConfig();
                }
            }
            else
            {
                config = new AppConfig();
            }

            Application.Run(new MainForm(config, configPath, appData, logDir));
        }
    }
}
