#!/usr/bin/env python3
"""Download and verify the pinned FDA label snapshot; never import into Pharmacy."""
import argparse
import hashlib
import json
import pathlib
import subprocess
import zipfile
from urllib.parse import urlparse


def verify(path, expected):
    import ijson
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    if expected.get('sha256') and digest.hexdigest() != expected['sha256']:
        raise ValueError(f'SHA-256 mismatch: {path.name}')
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if len(names) != 1 or not names[0].endswith('.json'):
            raise ValueError(f'Expected one JSON entry: {path.name}')
        with archive.open(names[0]) as stream:
            count = sum(1 for _ in ijson.items(stream, 'results.item'))
        # Reading the complete ZIP member also checks its CRC.
    if count != expected['records']:
        raise ValueError(f'Record count mismatch: {path.name}: {count}')
    return {'name': path.name, 'bytes': path.stat().st_size,
            'sha256': digest.hexdigest(), 'records': count}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('openfda-labels'))
    parser.add_argument('--verify-only', action='store_true')
    parser.add_argument('--manifest', type=pathlib.Path,
                        default=pathlib.Path(__file__).resolve().parents[1] / 'data/openfda/manifest.json')
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    report = []
    for entry in manifest['files']:
        url = entry['file']
        parsed = urlparse(url)
        if parsed.scheme != 'https' or parsed.hostname != 'download.open.fda.gov':
            raise ValueError('Unexpected download host')
        path = args.output / pathlib.PurePosixPath(parsed.path).name
        if not path.exists() and not args.verify_only:
            partial = path.with_suffix(path.suffix + '.partial')
            subprocess.run(['curl', '--fail', '--location', '--silent', '--show-error',
                            '--retry', '3', '--max-time', '1800', url, '-o', str(partial)], check=True)
            partial.replace(path)
        result = verify(path, entry)
        report.append(result)
        print(f"Verified {path.name}: {result['records']} records", flush=True)
    if sum(row['records'] for row in report) != manifest['total_records']:
        raise ValueError('Total records do not match manifest')
    (args.output / 'verification.json').write_text(json.dumps({
        'source': manifest['source'], 'export_date': manifest['export_date'],
        'total_records': manifest['total_records'], 'files': report}, indent=2) + '\n')
    (args.output / 'SHA256SUMS').write_text(''.join(
        f"{row['sha256']}  {row['name']}\n" for row in report))


if __name__ == '__main__':
    main()
