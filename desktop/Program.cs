using System.IO;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;

namespace Cas.Windows;

internal static class Program
{
    private const string Host = "cas-stage0.example";
    private const string Home = "https://" + Host + "/index.html";

    [STAThread]
    public static int Main(string[] args)
    {
        var smokePath = args.Length == 2 && args[0] == "--smoke" ? Path.GetFullPath(args[1]) : null;
        var app = new Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
        var browser = new WebView2 { DefaultBackgroundColor = System.Drawing.Color.FromArgb(9, 25, 35) };
        var shell = new Window
        {
            Title = "CAS · 即时海战试玩",
            Width = 1360, Height = 850, MinWidth = 740, MinHeight = 390,
            WindowStartupLocation = WindowStartupLocation.CenterScreen,
            Background = new SolidColorBrush(Color.FromRgb(9, 25, 35)),
            Content = browser,
            ShowInTaskbar = smokePath is null
        };
        var smokeTimeout = new DispatcherTimer { Interval = TimeSpan.FromSeconds(25) };
        var ended = false;

        void FinishSmoke(bool ok, object detail)
        {
            if (ended || smokePath is null) return;
            ended = true;
            smokeTimeout.Stop();
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(smokePath)!);
                File.WriteAllText(smokePath, JsonSerializer.Serialize(new { ok, detail }, new JsonSerializerOptions
                {
                    WriteIndented = true,
                    Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping
                }));
                app.Shutdown(ok ? 0 : 1);
            }
            catch
            {
                app.Shutdown(2);
            }
        }

        void Fail(string message)
        {
            if (smokePath is not null)
                FinishSmoke(false, message);
            else
            {
                MessageBox.Show(shell, message, "CAS 无法启动", MessageBoxButton.OK, MessageBoxImage.Error);
                app.Shutdown(1);
            }
        }

        shell.Closed += (_, _) => browser.Dispose();
        shell.Loaded += async (_, _) =>
        {
            try
            {
                var webRoot = Path.Combine(AppContext.BaseDirectory, "web");
                if (!File.Exists(Path.Combine(webRoot, "index.html")) ||
                    !File.Exists(Path.Combine(webRoot, "cas_core.wasm")) ||
                    !File.Exists(Path.Combine(webRoot, "engine-worker.js")))
                {
                    Fail("试玩包文件不完整。请重新解压完整文件夹，再双击 CAS.exe。");
                    return;
                }

                var profile = smokePath is null
                    ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "CASNaval", "Stage0", "WebView2")
                    : Path.Combine(Path.GetTempPath(), "CASNaval-Smoke", Guid.NewGuid().ToString("N"));
                var environment = await CoreWebView2Environment.CreateAsync(null, profile);
                await browser.EnsureCoreWebView2Async(environment);
                var core = browser.CoreWebView2;
                core.Settings.AreDevToolsEnabled = false;
                core.Settings.AreDefaultContextMenusEnabled = false;
                core.Settings.AreHostObjectsAllowed = false;
                core.Settings.IsStatusBarEnabled = false;
                core.Settings.IsWebMessageEnabled = smokePath is not null;
                core.SetVirtualHostNameToFolderMapping(Host, webRoot, CoreWebView2HostResourceAccessKind.DenyCors);
                core.NavigationStarting += (_, e) => e.Cancel = !string.Equals(e.Uri, Home, StringComparison.OrdinalIgnoreCase);
                core.NewWindowRequested += (_, e) => e.Handled = true;
                core.PermissionRequested += (_, e) => e.State = CoreWebView2PermissionState.Deny;
                core.AddWebResourceRequestedFilter("*", CoreWebView2WebResourceContext.All, CoreWebView2WebResourceRequestSourceKinds.All);
                core.WebResourceRequested += (_, e) =>
                {
                    if (Uri.TryCreate(e.Request.Uri, UriKind.Absolute, out var uri) &&
                        ((uri.Scheme == "https" && uri.Host == Host && uri.IsDefaultPort) || uri.Scheme is "data" or "blob")) return;
                    e.Response = environment.CreateWebResourceResponse(null, 403, "Offline bundle only", "Content-Type: text/plain");
                };
                core.NavigationCompleted += async (_, e) =>
                {
                    if (!e.IsSuccess)
                    {
                        Fail($"无法打开离线战术台（{e.WebErrorStatus}）。请确认试玩包已完整解压。");
                        return;
                    }
                    if (smokePath is null) return;
                    try { await core.ExecuteScriptAsync(SmokeScript); }
                    catch (Exception error) { FinishSmoke(false, error.Message); }
                };
                if (smokePath is not null)
                {
                    core.WebMessageReceived += (_, e) =>
                    {
                        if (!string.Equals(e.Source, Home, StringComparison.OrdinalIgnoreCase)) return;
                        try
                        {
                            using var payload = JsonDocument.Parse(e.WebMessageAsJson);
                            var message = payload.RootElement;
                            if (message.GetProperty("type").GetString() != "cas_native_smoke") return;
                            FinishSmoke(message.GetProperty("ok").GetBoolean(), new
                            {
                                browser = environment.BrowserVersionString,
                                origin = e.Source,
                                evidence = message.Clone()
                            });
                        }
                        catch (Exception error) { FinishSmoke(false, error.Message); }
                    };
                }
                core.Navigate(Home);
            }
            catch (WebView2RuntimeNotFoundException)
            {
                Fail("本机未安装 Microsoft Edge WebView2 Runtime。安装后再打开 CAS.exe。");
            }
            catch (Exception error) { Fail($"战术台启动失败：{error.Message}"); }
        };
        if (smokePath is not null)
        {
            smokeTimeout.Tick += (_, _) => FinishSmoke(false, "WebView2 在 25 秒内没有返回战斗内核结果。");
            smokeTimeout.Start();
        }
        return app.Run(shell);
    }

    private const string SmokeScript = """
        (async () => {
          let worker;
          const send = data => chrome.webview.postMessage({ type: 'cas_native_smoke', ...data });
          try {
            const button = label => [...document.querySelectorAll('button')].find(b =>
              b.textContent.trim() === label || b.getAttribute('aria-label') === label);
            const waitFor = async (description, check, ms = 8000) => {
              const deadline = Date.now() + ms;
              for (;;) {
                const value = check();
                if (value) return value;
                if (Date.now() >= deadline) throw Error('Timed out waiting for ' + description);
                await new Promise(resolve => setTimeout(resolve, 75));
              }
            };
            const field = (id, value) => {
              const input = document.getElementById(id);
              Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
              input.dispatchEvent(new Event('input', { bubbles: true }));
            };
            await waitFor('the local account login', () => document.querySelector('main.login-screen'));
            const user = 'CASSmokeWindows';
            const password = 'CAS offline smoke 2026';
            button('新用户，创建账号').click();
            await waitFor('the registration form', () => button('注册并进入母港'));
            field('account-username', user);
            field('account-password', password);
            button('注册并进入母港').click();
            await waitFor('the authenticated harbor', () => document.querySelector('.growth-campaign-entry'));
            const localProfile = JSON.parse(localStorage.getItem('cas.accounts.local.v1')).find(record => record.name === user);
            if (!localProfile?.id || localProfile.verifier === password) throw Error('The offline account was not stored as a verifier.');
            document.querySelector('.growth-campaign-entry').click();
            await waitFor('16 allied campaign stages', () => document.querySelectorAll('[data-stage-id^="CAMP-ALLIES-"]').length === 16);
            document.querySelector('[data-stage-id="CAMP-ALLIES-03"] summary').click();
            await waitFor('Cape St. George primary source in the UI', () => document.querySelector('[data-source-stage="CAMP-ALLIES-03"]'));
            button('轴心战线').click();
            await waitFor('16 Axis stages and their Cape record', () => document.querySelectorAll('[data-stage-id^="CAMP-AXIS-"]').length === 16 &&
              document.querySelector('[data-source-stage="CAMP-AXIS-03"]'));
            document.querySelector('[data-stage-id="CAMP-AXIS-16"] summary').click();
            const midnight = await waitFor('the offline legacy midnight fleet deployment', () => document.querySelector('[data-legacy-stage="CAMP-AXIS-16"]'));
            const placement = () => [...midnight.querySelectorAll('svg.archive-deployment g')].map(mark => mark.getAttribute('transform'));
            const originalPlacement = placement();
            if (originalPlacement.length !== 91) throw Error('The old midnight fleet chart did not render 91 positions.');
            midnight.querySelector('.archive-placement-toggle input').click();
            await waitFor('the old midnight fleet default formation chart', () =>
              placement().length === 91 && placement().some((mark, i) => mark !== originalPlacement[i]));
            button('返回母港').click();
            (await waitFor('main harbor controls', () => button('打开主菜单'))).click();
            (await waitFor('continue exercise', () => {
              const next = button('继续演习');
              return next && !next.disabled && next;
            })).click();
            worker = new Worker(new URL('./engine-worker.js', document.baseURI));
            let id = 0;
            const request = payload => new Promise((resolve, reject) => {
              const current = ++id;
              worker.onmessage = ({ data }) => {
                if (data.id !== current) return;
                if (data.response.ok) resolve(data.response.data);
                else reject(Error(data.response.error));
              };
              worker.onerror = e => reject(Error(e.message || 'Worker error'));
              worker.postMessage({ id: current, request: payload });
            });
            const info = await request({ op: 'info' });
            if (!info.realtimeVersion || info.tickSeconds !== 1) {
              throw Error('Unexpected engine identity: ' + JSON.stringify(info));
            }
            const start = await request({ op: 'new', seed: 6106, side: 'allies', enemy: 'coord', realtime: true });
            const after = await request({ op: 'step', seconds: 1 });
            const count = start.ships?.length;
            if (start.tick !== 0 || after.tick !== 1 || count !== 5) {
              throw Error('The battle state did not advance: ' + JSON.stringify({ tickBefore: start.tick, tickAfter: after.tick, count }));
            }
            if (!start.realtimeGunnery || start.version !== info.realtimeVersion ||
                !start.ships.every(ship => ship.systems.guns.every(mount => Number.isInteger(mount.readyTick)))) {
              throw Error('The active realtime guns and their reload clocks were not exposed.');
            }
            await request({ op: 'ai', fleet: start.fleets[0].id, profile: 'coord', mode: 'auto', move: true, gun: true, torpedo: true });
            const moved = await request({ op: 'step', seconds: 359 });
            if (moved.tick !== 360) throw Error('The save checkpoint was not reached.');
            const save = await request({ op: 'save' });
            if (save.version !== info.realtimeVersion) throw Error('The save did not preserve the active rules version.');
            const key = 'cas.native-smoke';
            localStorage.setItem(key, JSON.stringify(save));
            const stored = JSON.parse(localStorage.getItem(key));
            localStorage.removeItem(key);
            const past = await request({ op: 'replay', save: stored, tick: 1 });
            const replay = await request({ op: 'replay', save: stored });
            const still = await request({ op: 'observe' });
            const restored = await request({ op: 'load', save: stored });
            const same = observation => JSON.stringify(observation) === JSON.stringify(moved);
            if (past.tick !== 1 || !same(replay) || !same(still) || !same(restored)) {
              throw Error('The offline save, load and replay did not agree.');
            }
            const night = await request({ op: 'new', seed: 6106, variant: 'night', realtime: true });
            if (night.variant !== 'night' || night.ships?.length !== 5 || night.version !== info.realtimeVersion) {
              throw Error('The offline night exercise did not start.');
            }
            const campaign = await request({ op: 'campaign' });
            const rows = campaign.scenarios;
            if (rows?.length !== 16 || rows.filter(row => row.playable && row.runtime?.historicalReady === false).length !== 2 ||
              rows.filter(row => row.cas?.import).length !== 11) throw Error('The offline historical catalogue did not load.');
            const cape = await request({ op: 'new_campaign', id: 'CAMP-AXIS-03', difficulty: 'story', seed: 6106 });
            const capeSave = await request({ op: 'save' });
            if (cape.ships.length !== 5 || cape.fleets.length !== 2 || cape.campaign.stageId !== 'CAMP-AXIS-03' ||
                cape.environment.visibility !== 10 || JSON.stringify(cape) !== JSON.stringify(await request({ op: 'replay', save: capeSave }))) {
              throw Error('The packaged Cape St. George scenario did not open or replay.');
            }
            const channel = await request({ op: 'new_campaign', id: 'CAMP-AXIS-01', difficulty: 'story', seed: 53 });
            const channelSave = await request({ op: 'save' });
            if (channel.ships.length !== 3 || channel.fleets.length !== 3 || channel.environment.visibility !== 5 ||
                channel.ships.some(ship => ship.classId !== ship.characterId) ||
                JSON.stringify(channel) !== JSON.stringify(await request({ op: 'replay', save: channelSave }))) {
              throw Error('The packaged Channel Action did not open or replay.');
            }
            const legacy = await request({ op: 'campaign_detail', id: 'CAMP-AXIS-16' });
            if (legacy.record || legacy.legacy?.ships?.length !== 91 ||
                legacy.legacy?.post_default_formation_setup?.ships?.length !== 91 || legacy.legacy?.playable !== false) {
              throw Error('The old deployment and resolved opening were not preserved as separate source data.');
            }
            const ready = () => document.querySelector('canvas') && document.querySelectorAll('[data-ship]').length === 5;
            const deadline = Date.now() + 8000;
            while (!ready() && Date.now() < deadline) await new Promise(resolve => setTimeout(resolve, 75));
            if (!ready()) throw Error('The packaged battle map did not render five friendly ships.');
            if (!document.querySelector('.realtime-badge')) throw Error('The playable exercise did not open in realtime gunnery mode.');
            const shipTab = [...document.querySelectorAll('.staff-tabs button')].find(button => button.textContent.trim() === '舰况');
            if (!shipTab) throw Error('The packaged ship status tab was missing.');
            shipTab.click();
            const readyPortrait = () => [...document.querySelectorAll('.ship-portrait img')].find(img => img.complete && img.naturalWidth > 0);
            const portraitDeadline = Date.now() + 6000;
            while (!readyPortrait() && Date.now() < portraitDeadline) await new Promise(resolve => setTimeout(resolve, 75));
            const portrait = readyPortrait();
            if (!portrait) throw Error('The packaged ship status portrait did not load offline.');
            (await waitFor('battle return to harbor', () => button('母港'))).click();
            (await waitFor('harbor menu after the exercise', () => button('打开主菜单'))).click();
            (await waitFor('logout action', () => button('退出登录'))).click();
            await waitFor('login after logout', () => document.querySelector('main.login-screen'));
            field('account-username', user);
            field('account-password', password);
            button('登录并进入母港').click();
            await waitFor('login restoring the same profile', () => document.querySelector('.growth-campaign-entry'));
            if (!localStorage.getItem('cas.profile.' + localProfile.id + '.cas.exercise.autosave.v1')) {
              throw Error('The exercise was not stored under the local account.');
            }
            const hash = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify(moved)));
            const stateSha256 = [...new Uint8Array(hash)].map(n => n.toString(16).padStart(2, '0')).join('');
            send({ ok: true, version: start.version, baselineVersion: info.version, scenario: info.scenario, tickBefore: start.tick, tickAfter: after.tick,
              ownShips: count, savedTick: moved.tick, replayTick: replay.tick, saveReplayMatch: true, stateSha256,
              battleMapRendered: true, harborNavigation: true, nightExerciseStarted: true, historicalCatalogueRows: rows.length,
              historicalStageIds: 32, historicalSourceRecords: 11, playableAdaptations: 2, capeReplay: true, channelReplay: true,
              legacyMidnightShips: 91, legacyMidnightFormationSwitch: true,
              offlineLocalAccountRoundtrip: true,
              shipPortrait: portrait.closest('[data-character]').dataset.character,
              viewport: [innerWidth, innerHeight] });
          } catch (e) {
            send({ ok: false, error: String(e) });
          } finally {
            worker?.terminate();
          }
        })();
        """;
}
