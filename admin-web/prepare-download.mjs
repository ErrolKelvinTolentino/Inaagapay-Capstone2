import { createHash, randomUUID } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, open, readFile, rename, rm, stat } from 'node:fs/promises';
import { dirname } from 'node:path';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';

const apkPath = fileURLToPath(new URL('./downloads/inaagapay.apk', import.meta.url));
const releasePath = fileURLToPath(new URL('./downloads/release.json', import.meta.url));
const minimumBytes = 1024;
const maximumBytes = 1_000_000_000;
const maximumDirectoryBytes = 32 * 1024 * 1024;

class PreparationError extends Error {}

function artifactUrl(value) {
  let url;
  try {
    url = new URL(value);
  } catch {
    throw new PreparationError('APK_ARTIFACT_URL must be a direct HTTPS URL to the official APK.');
  }
  if (url.protocol !== 'https:' || url.username || url.password || url.hash) {
    throw new PreparationError('APK_ARTIFACT_URL and its redirects must use HTTPS without URL credentials or fragments.');
  }
  return url;
}

function expectedHash(value, required) {
  if (!value && !required) return undefined;
  if (!/^[a-f\d]{64}$/i.test(value ?? '')) {
    throw new PreparationError('Set APK_ARTIFACT_SHA256 to the official APK\'s 64-character SHA-256 hash.');
  }
  return value.toLowerCase();
}

async function readExactly(file, length, position) {
  const buffer = Buffer.alloc(length);
  const { bytesRead } = await file.read(buffer, 0, length, position);
  if (bytesRead !== length) throw new PreparationError('The APK archive is truncated. Prepare a complete release APK.');
  return buffer;
}

// APKs are ZIP archives. Check the directory and required Android entries,
// without loading a large APK or relying on an installed archive utility.
async function validateApk(path) {
  const info = await stat(path);
  if (!info.isFile() || info.size < minimumBytes || info.size > maximumBytes) {
    throw new PreparationError('The APK must be a complete file between 1 KB and 1 GB.');
  }
  const file = await open(path, 'r');
  try {
    const signature = await readExactly(file, 4, 0);
    if (signature.readUInt32LE(0) !== 0x04034b50) {
      throw new PreparationError('The download is not an APK ZIP archive. Use the direct binary asset, not an HTML release page.');
    }

    const tailLength = Math.min(info.size, 22 + 65535);
    const tail = await readExactly(file, tailLength, info.size - tailLength);
    let endOffset = -1;
    for (let offset = tail.length - 22; offset >= 0; offset -= 1) {
      if (tail.readUInt32LE(offset) === 0x06054b50
          && offset + 22 + tail.readUInt16LE(offset + 20) === tail.length) {
        endOffset = offset;
        break;
      }
    }
    if (endOffset < 0) throw new PreparationError('The APK archive is incomplete or corrupt. Prepare a complete release APK.');
    const count = tail.readUInt16LE(endOffset + 10);
    const directoryBytes = tail.readUInt32LE(endOffset + 12);
    const directoryOffset = tail.readUInt32LE(endOffset + 16);
    const endPosition = info.size - tailLength + endOffset;
    if (tail.readUInt16LE(endOffset + 4) !== 0 || tail.readUInt16LE(endOffset + 6) !== 0
        || count < 2 || count === 0xffff || tail.readUInt16LE(endOffset + 8) !== count
        || directoryBytes > maximumDirectoryBytes || directoryOffset + directoryBytes !== endPosition) {
      throw new PreparationError('The APK ZIP directory is invalid or unsupported. Prepare a standard Android release APK.');
    }

    const directory = await readExactly(file, directoryBytes, directoryOffset);
    const required = new Set(['AndroidManifest.xml', 'classes.dex']);
    let offset = 0;
    for (let index = 0; index < count; index += 1) {
      if (offset + 46 > directory.length || directory.readUInt32LE(offset) !== 0x02014b50) {
        throw new PreparationError('The APK ZIP directory is corrupt. Prepare a complete release APK.');
      }
      const flags = directory.readUInt16LE(offset + 8);
      const method = directory.readUInt16LE(offset + 10);
      const compressedBytes = directory.readUInt32LE(offset + 20);
      const uncompressedBytes = directory.readUInt32LE(offset + 24);
      const nameBytes = directory.readUInt16LE(offset + 28);
      const extraBytes = directory.readUInt16LE(offset + 30);
      const commentBytes = directory.readUInt16LE(offset + 32);
      const localOffset = directory.readUInt32LE(offset + 42);
      const nextOffset = offset + 46 + nameBytes + extraBytes + commentBytes;
      if (nextOffset > directory.length || localOffset + 30 > directoryOffset) {
        throw new PreparationError('The APK ZIP entry is corrupt. Prepare a complete release APK.');
      }
      const name = directory.toString('utf8', offset + 46, offset + 46 + nameBytes);
      if (required.has(name)) {
        const local = await readExactly(file, 30, localOffset);
        const localNameBytes = local.readUInt16LE(26);
        const localExtraBytes = local.readUInt16LE(28);
        if (local.readUInt32LE(0) !== 0x04034b50 || flags & 1
            || local.readUInt16LE(8) !== method || compressedBytes === 0 || uncompressedBytes === 0
            || localOffset + 30 + localNameBytes + localExtraBytes + compressedBytes > directoryOffset) {
          throw new PreparationError('A required Android APK entry is invalid. Prepare a complete release APK.');
        }
        const localName = await readExactly(file, localNameBytes, localOffset + 30);
        if (localName.toString('utf8') !== name) {
          throw new PreparationError('The APK ZIP entry names do not match. Prepare a complete release APK.');
        }
        required.delete(name);
      }
      offset = nextOffset;
    }
    if (offset !== directory.length || required.size !== 0) {
      throw new PreparationError('The archive is missing AndroidManifest.xml or classes.dex, or has an invalid directory. Use the official release APK.');
    }
  } finally {
    await file.close();
  }
  return info.size;
}

async function hashFile(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

async function fetchArtifact(initialUrl, signal) {
  let url = initialUrl;
  for (let redirects = 0; redirects <= 5; redirects += 1) {
    let response;
    try {
      response = await fetch(url, { redirect: 'manual', signal, headers: { 'Accept-Encoding': 'identity' } });
    } catch {
      throw new PreparationError('The APK download failed. Check the build artifact URL, its availability, and network access.');
    }
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get('location');
      await response.body?.cancel();
      if (!location || redirects === 5) break;
      url = artifactUrl(new URL(location, url).href);
      continue;
    }
    if (response.status !== 200 || !response.body) {
      await response.body?.cancel();
      throw new PreparationError('The APK artifact did not return a complete download. Check that the direct APK URL is publicly accessible.');
    }
    const type = response.headers.get('content-type') ?? '';
    const length = Number(response.headers.get('content-length'));
    if (type.toLowerCase().includes('text/html') || length > maximumBytes) {
      await response.body.cancel();
      throw new PreparationError('The artifact is an HTML page or exceeds 1 GB. Use the direct official APK binary.');
    }
    return response;
  }
  throw new PreparationError('The APK artifact has an invalid redirect chain. Use a direct HTTPS binary asset URL.');
}

async function prepareDownload() {
  let remoteValue = process.env.APK_ARTIFACT_URL?.trim();
  let hash = expectedHash(process.env.APK_ARTIFACT_SHA256?.trim(), Boolean(remoteValue));
  if (!remoteValue) {
    let size;
    try {
      size = await validateApk(apkPath);
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
    if (size !== undefined) {
      if (hash && await hashFile(apkPath) !== hash) {
        throw new PreparationError('The local APK SHA-256 does not match. Prepare the expected official release APK.');
      }
      console.log(`Using validated local APK (${(size / 1_000_000).toFixed(1)} MB).`);
      return;
    }

    // Git deployments omit generated APKs. Fetch the specific official release
    // pinned in source, without requiring project-level environment setup.
    let release;
    try {
      release = JSON.parse(await readFile(releasePath, 'utf8'));
    } catch (error) {
      if (error.code === 'ENOENT') {
        throw new PreparationError('APK is missing. Publish downloads/release.json with the official APK URL and SHA-256, run scripts/prepare-apk.ps1 locally, or set APK_ARTIFACT_URL and APK_ARTIFACT_SHA256 in the hosting build environment.');
      }
      throw new PreparationError('downloads/release.json must contain valid JSON with the official APK url and sha256.');
    }
    remoteValue = release?.url;
    hash = expectedHash(release?.sha256, true);
  }

  const url = artifactUrl(remoteValue);
  await mkdir(dirname(apkPath), { recursive: true });
  const partialPath = fileURLToPath(new URL(`./downloads/inaagapay.${randomUUID()}.partial`, import.meta.url));
  try {
    const response = await fetchArtifact(url, AbortSignal.timeout(5 * 60 * 1000));
    const digest = createHash('sha256');
    let size = 0;
    const verifier = new Transform({
      transform(chunk, encoding, callback) {
        size += chunk.length;
        if (size > maximumBytes) {
          callback(new PreparationError('The APK exceeds 1 GB. Prepare a smaller Android release APK.'));
          return;
        }
        digest.update(chunk);
        callback(null, chunk);
      },
    });
    try {
      await pipeline(Readable.fromWeb(response.body), verifier, createWriteStream(partialPath, { flags: 'wx' }));
    } catch (error) {
      if (error instanceof PreparationError) throw error;
      throw new PreparationError('The APK transfer failed. Check the artifact availability and hosting build disk space, then retry.');
    }
    if (digest.digest('hex') !== hash) {
      throw new PreparationError('The downloaded APK SHA-256 does not match. Check APK_ARTIFACT_SHA256 against the official release APK.');
    }
    await validateApk(partialPath);
    // Replace the previous APK only after the entire pinned artifact is valid.
    await rename(partialPath, apkPath);
    console.log(`APK prepared and verified (${(size / 1_000_000).toFixed(1)} MB).`);
  } finally {
    await rm(partialPath, { force: true });
  }
}

try {
  await prepareDownload();
} catch (error) {
  console.error(error instanceof PreparationError ? error.message : 'APK preparation failed. Check the release APK and build output directory permissions.');
  process.exitCode = 1;
}
