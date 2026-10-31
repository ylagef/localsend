"""Verify the exact APK identity and certificate against host-local signing configuration."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys


def verify_metadata(package_text, certificate_text, version, build_number, expected_certificate):
    package = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'", package_text)
    if not package or package.groups() != ('org.localsend.localsend_app', str(build_number * 10 + 3), version):
        raise ValueError('Unexpected APK package or version')
    native = re.search(r'^native-code: (.+)$', package_text, re.M)
    if not native or native.group(1).strip() != "'arm64-v8a'":
        raise ValueError('Expected an arm64-only APK')
    fingerprints = re.findall(r'^Signer #\d+ certificate SHA-256 digest: (\w+)$', certificate_text, re.M)
    if len(fingerprints) != 1 or fingerprints[0].lower() != expected_certificate.lower():
        raise ValueError('APK certificate does not match the retained personal signing key')


def main():
    apk, version, number = sys.argv[1:]
    config = {}
    for line in Path(os.environ['LOCALSEND_ANDROID_KEY_PROPERTIES']).read_text().splitlines():
        if '=' in line and not line.lstrip().startswith('#'):
            key, value = line.split('=', 1)
            config[key.strip()] = value.strip()
    env = dict(os.environ, LOCALSEND_VERIFY_STORE_PASSWORD=config['storePassword'])
    cert = subprocess.check_output([
        'keytool', '-exportcert', '-keystore', config['storeFile'], '-alias', config['keyAlias'],
        '-storepass:env', 'LOCALSEND_VERIFY_STORE_PASSWORD',
    ], env=env, stderr=subprocess.PIPE)
    expected = hashlib.sha256(cert).hexdigest()
    verify_metadata(Path(apk + '.package.txt').read_text(), Path(apk + '.certificate.txt').read_text(), version, int(number), expected)
    print('APK package, versionCode, ABI and retained signing certificate verified.')


if __name__ == '__main__':
    main()
