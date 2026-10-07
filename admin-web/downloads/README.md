# InaAgapay APK download

The website serves `inaagapay.apk` directly from this directory. The login page
links to `download.html`, and the midwife profile menu opens a QR screen for:

`https://inaagapay-capstone.vercel.app/download.html?auto=1`

Android browsers request the APK automatically after opening that QR link.
Browsers that require a user gesture keep the **Get InaAgapay** and retry buttons
available. Downloads use the browser's download manager, usually the public
**Downloads** folder. The website cannot override the user's browser save
location or confirmation settings. It never saves the APK in Flutter's private
application data directory.

## Prepare a build

From the repository root, with Flutter, the Android SDK, and the app's `.env`
configured:

```powershell
./scripts/prepare-apk.ps1
```

This builds a universal release APK with the midwife QR link configured for the
official website, validates its archive, and copies it to
`admin-web/downloads/inaagapay.apk`. It prints the size and SHA-256 hash. To use an
existing signed release APK instead:

```powershell
./scripts/prepare-apk.ps1 -ApkPath 'C:/path/to/official-release.apk'
```

The script uses the app's existing signing configuration. Currently
`android/app/build.gradle.kts` signs release builds with this machine's debug
key. Keep the signing key used by already-installed builds when distributing
updates, or supply the team's signed release APK with `-ApkPath`.

When publishing another version, update `APP.version` and the initial
`app-version` label in `download.html` to match the APK's version.

For another public host, build with `-DownloadPageUrl` set to its complete
`download.html` URL. The Flutter `APP_DOWNLOAD_PAGE_URL` build setting controls
the midwife QR link; no API keys are part of that link.

## Publish the file with the website

The APK is a generated artifact excluded from Git and Vercel's CLI source
upload. Clean Git deployments fetch the official release pinned in
`downloads/release.json`, verify its SHA-256 and Android archive, and include
it in the website. Both hosting root configurations use this same manifest.
No Vercel environment variables are needed for the pinned release.

When publishing a new APK:

1. Run `./scripts/prepare-apk.ps1` and keep its SHA-256 value.
2. Upload `admin-web/downloads/inaagapay.apk` to the team's artifact storage.
   Use a fixed, direct HTTPS file URL. For example, an APK attached to a specific
   GitHub release can be the build input. People downloading from the website
   will still receive the file from the website's own download URL.
3. Update `admin-web/downloads/release.json` with the specific release asset URL
   and the SHA-256 printed by `prepare-apk.ps1`:

   ```json
   {
     "url": "https://github.com/<team>/<repository>/releases/download/<tag>/inaagapay.apk",
     "sha256": "<64-character SHA-256>"
   }
   ```

   For a hosting-specific override, set both of these environment variables in
   the Vercel project for the environment being deployed:

   ```text
   APK_ARTIFACT_URL=<direct HTTPS URL of the prepared APK>
   APK_ARTIFACT_SHA256=<64-character SHA-256 printed by prepare-apk.ps1>
   ```

4. Commit the manifest and deploy the updated website. Both Vercel configurations invoke
   `prepare-download.mjs`, which downloads the artifact during the hosted build,
   verifies the pinned hash and APK format, and includes it in the static output.
   A missing or invalid artifact stops the build with an actionable error.

For a local preview, `prepare-apk.ps1` already places the APK beside the website;
`node admin-web/prepare-download.mjs` can validate that file without downloading
it again. When a remote artifact URL is configured, its pinned artifact is used.

Both Vercel configurations support either repository-root hosting or an
`admin-web` project root. They explicitly use `.` as the static output directory,
so the APK preparation build does not require a generated `public` directory:

- `/downloads/inaagapay.apk` serves the APK.
- `/apk` rewrites to the same file; it does not redirect to GitHub.
- `/app` opens `download.html?auto=1`.

The APK endpoints send `Content-Disposition: attachment;
filename="inaagapay.apk"`, the Android package content type, and a revalidation
cache policy. Other hosts need equivalent response headers.

Vercel's Hobby CLI source upload limit is 100 MB. Fetching the APK during the
hosted build keeps it out of that source upload. See
[Vercel's upload limits](https://vercel.com/docs/limits#static-file-uploads) and
[custom build commands](https://vercel.com/docs/builds/configure-a-build).

After publishing, check that the APK URL returns **200**, the attachment header,
and a real APK instead of an error page. Test a manual download and scan the QR
with another Android phone; confirm `inaagapay.apk` appears in the browser's
Downloads and in **Files > Downloads** with the default browser save settings.
