# Task 10.3: step by step, for tomorrow

You need about 2–3 hours, mostly download time. Everything runs on your own Windows machine with a dev daemon, the same way you ran the M1 Valheim checks. Nothing is installed as a service, and no accounts or firewall rules are created.

At the end, send me what you saw at each **Record** point. I'll write it into `docs/milestones/m3.md` and won't mark anything passed for you.

## 0. Before you start

- **A Steam account with Steam Guard by email.** Your spike's email account is ideal. Mobile approval also works, but the email code tests the "code prompt reaches the desktop" path better. If the account owns DayZ, you can also join the server in steps 9–10.
- **About 20 GB free on the drive** where the data directory will live. The daemon wants twice the 3.5 GB server size free before it installs, and 10+ mods add a few more GB.
- **10–12 workshop mod IDs** from the DayZ workshop. Open each item's page and copy the number after `?id=`. Pasting whole links also works.
  - Include **Community Framework** (`1559212036`).
  - Add other popular mods, e.g. Dabs Framework, VPPAdminTools, Community Online Tools, Code Lock, BaseBuildingPlus or BuilderItems.
  - Pick at least one mod that **updates often**; step 8 depends on it.
  - Some mods need others loaded first. Keep any dependency (CF, Dabs Framework) above the mods that use it.

## 1. Build and prepare (PowerShell, from the repo root)

```powershell
mkdir F:\yagura-m3\data\plugins
Copy-Item -Recurse plugins\dayz F:\yagura-m3\data\plugins\
cd apps\yagurad
mise exec -- dart build cli -t bin/yagurad.dart -o F:/yagura-m3/build
```

It must be the compiled `yagurad.exe`. Under `dart run`, Start fails.

## 2. Start the daemon (terminal A, leave it running)

```powershell
F:\yagura-m3\build\bundle\bin\yagurad.exe run --console --dev --data-dir F:\yagura-m3\data 2>&1 | Tee-Object F:\yagura-m3\console.log
```

It prints `DEV MODE: unauthenticated, localhost only`. The `Tee-Object` keeps a copy of the console output so you can search it for the password in step 5.

## 3. Start the desktop app (terminal B)

```powershell
cd apps\yagura_desktop
mise exec -- flutter run -d windows
```

On the **Development daemon** card, press **Manage**. No pairing is needed.

## 4. Add the Steam account (exit criterion 2)

1. Click the **Steam accounts** icon in the top bar.
2. Enter the **Steam username** and **Password**. Leave **Remember the password** off, then press **Add account**.
3. A **Steam Guard code** dialog should open by itself, with the text "Enter the code Steam emailed to the address of …" and a countdown.
   - Email can be slow; in the spike it once took over 10 minutes. The dialog waits up to 15 minutes.
4. Type the code from the email and press **Submit**.
5. The account card should show **ready**, and the `add_steam_account` operation (bottom panel) should show **succeeded**.

**Record:**
- Did the prompt appear in the desktop by itself?
- How long did the email take?
- Did the login complete?
- Any error text you saw.

## 5. Search for the password (still criterion 2)

Do this after step 4, and again at the very end.

1. Stop the daemon first: Ctrl+C in terminal A, so the logs are flushed.
2. Paste this into PowerShell. It asks for the password without showing it and prints only the names of files that contain it. It checks both UTF-8 and UTF-16 text.

```powershell
$s = Read-Host -AsSecureString "Steam password"
$p = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
$pats = @([Text.Encoding]::UTF8.GetBytes($p), [Text.Encoding]::Unicode.GetBytes($p))
$hits = 0
Get-ChildItem F:\yagura-m3\data, F:\yagura-m3\console.log -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
  try { $b = [IO.File]::ReadAllBytes($_.FullName) } catch { Write-Host "unreadable: $($_.FullName)"; return }
  foreach ($pat in $pats) {
    for ($i = [Array]::IndexOf($b, $pat[0]); $i -ge 0 -and $i -le $b.Length - $pat.Length; $i = [Array]::IndexOf($b, $pat[0], $i + 1)) {
      $ok = $true; for ($j = 1; $j -lt $pat.Length; $j++) { if ($b[$i+$j] -ne $pat[$j]) { $ok = $false; break } }
      if ($ok) { Write-Host "FOUND in $($_.FullName)"; $hits++; break }
    }
  }
}
"$hits file(s) contain the password"; $p = $null
```

This covers the data directory (`yagura.db` and its WAL file, `logs\`, all of `steamcmd\` including `config.vdf`) and the console copy.

**Record:** the final count, which should be 0, and any "unreadable" lines.

3. Restart the daemon with the same command as in step 2. The app reconnects by itself.

## 6. Create the DayZ instance and install it

1. Press **+** (Create instance), choose **DayZ Server** under **Game**, name it, and press **Create**.
2. **Initial settings** opens. Set the three passwords (Server password can stay empty if you want an open server) and press **Save**.
3. In the instance detail, set **Steam account** to your account.
4. Press **Install**. This downloads about 3 GB through SteamCMD using the cached login, so Steam Guard should not ask again. Watch the progress bar in the `install` card.

## 7. Mods to a running server in one action (criterion 3, part 1)

1. Open the **Mods** tab and paste your IDs into **Workshop ids or links**.
2. Choose **client** as the role (use **server** only for mods meant as server mods) and press **Add**.
3. Order them with **Load earlier** / **Load later**, then press **Save**.
4. Press **Start** once. That one action should download every mod, link them, copy their keys and launch the server.
5. Wait for the instance to show **running**. That happens when the server prints "Dedicated host created" in its RPT log; that line is my guess, see the checks below.

**Checks** (`<id>` is the folder under `F:\yagura-m3\data\instances\`):

```powershell
$srv = "F:\yagura-m3\data\instances\<id>\server"
Get-ChildItem $srv -Filter '@*' | Select-Object Name, LinkType, Target   # every mod: LinkType Junction
Get-ChildItem "$srv\keys" -Filter *.bikey | Select-Object Name           # one key per mod (plus dayz.bikey)
Get-Content (Get-ChildItem "$srv\profiles\*.RPT" | Sort-Object LastWriteTime | Select-Object -Last 1) | Select-String -Pattern 'BattlEye|Dedicated host|mod|error' | Select-Object -First 60
```

**Record:**
- Did one Start do everything?
- Roughly how long did it take?
- Are the `@…` entries **Junction**s? If some are plain folders, the copy fallback was used.
- Did the keys arrive?
- Did the instance reach **running**? If it stayed "starting" until it failed after 5 minutes, send me the RPT's last 30 lines. The ready line is then wrong.

## 8. Mod update (criterion 3, part 2)

This is the one part you can't control: a mod author has to publish an update.

1. On the **Mods** tab, press **Check for updates**. Any mod with a new version shows **Update available**.
2. If one does, press **Update**. It stops the server, downloads only the changed mod, re-links only that one and restarts the server.

**Check:**
- Run the `Get-ChildItem $srv -Filter '@*'` line from step 7 before and after. Only the updated mod's **Target** should change.
- The instance should come back to **running**.

If nothing updates during your session, leave it and press **Check for updates** later. The daemon also checks by itself every 6 hours. If no update happens before you want to finish, record "update not observed". The in-process test already covers the mechanism, so it's then your call whether that's enough for criterion 3.

## 9. A3: does BattlEye load mods through junctions?

The RPT lines from step 7 should show BattlEye initialising and the mods loading, with no "cannot open" or signature errors.

The best proof is joining: if the account owns DayZ, start the DayZ client with the same mods and **Direct connect** to `127.0.0.1:2302`.
- No BattlEye kick and no signature kick means **A3 holds**.
- A kick or "BattlEye initialization failed" means **A3 fails**. Copy the message for me.

I'm also unsure about `-BEpath=yagura/battleye`, which may need BattlEye's DLL in that folder. A BattlEye error is the sign it's wrong.

## 10. A2: does DayZ save and exit on Ctrl+C?

1. Note the newest timestamp under `server\mpmissions\<mission>\storage_*\`. If you joined, move around first so there is something to save.
2. Press **Stop**.

**Record:**
- How long did the stop take?
- Does the stop operation or the daemon console say it stopped gracefully, or was the server killed after the 60-second grace?
- Did the storage files get a newer timestamp?

If the server ignored the signal and was killed, A2 fails, and I'll switch the plugin to `kill`.

## 11. Finish

1. Run step 5's scan once more.
2. Send me the **Record** answers from steps 4, 5 and 7–10, and any odd messages.

I'll write them into `docs/milestones/m3.md` and adjust the plugin where A2, A3, the ready line or `-BEpath` turned out wrong. Then we can run `/opsx:archive`.
