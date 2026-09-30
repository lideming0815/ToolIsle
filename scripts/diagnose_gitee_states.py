#!/usr/bin/env python3
"""Read-only, bounded state diagnostics. Prompt for token; never print/store issues or credentials."""
import argparse
import collections
import getpass
import json
import re
import ssl
import sys
import urllib.error
import urllib.parse
import urllib.request

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repository', action='append', required=True, help='owner/repo; repeat to inspect another explicitly selected repository')
    parser.add_argument('--pages', type=int, default=2, choices=range(1, 21), metavar='1..20')
    args = parser.parse_args()
    if any(not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', r) or any(p in ('.', '..') for p in r.split('/')) for r in args.repository):
        parser.error('Expected owner/repo, without URL, credentials, or query parameters.')
    token = getpass.getpass('Gitee token (hidden; not saved): ').strip()
    if not token or len(token) > 4096 or any(ord(c) < 32 or ord(c) == 127 for c in token):
        parser.error('Invalid token format.')
    opener = urllib.request.build_opener(NoRedirect(), urllib.request.HTTPSHandler(context=ssl.create_default_context()))
    counts = collections.Counter()
    pages_read = 0
    capped = False
    try:
        for repository in args.repository:
            for page in range(1, args.pages + 1):
                query = urllib.parse.urlencode({'state': 'all', 'page': page, 'per_page': 50})
                path = '/'.join(urllib.parse.quote(p, safe='') for p in repository.split('/'))
                request = urllib.request.Request('https://gitee.com/api/v5/repos/' + path + '/issues?' + query,
                    headers={'Authorization': 'Bearer ' + token, 'Accept': 'application/json', 'User-Agent': 'ToolIsle-Local-State-Diagnostic/1'}, method='GET')
                with opener.open(request, timeout=25) as response:
                    data = response.read(8 * 1024 * 1024 + 1)
                if len(data) > 8 * 1024 * 1024:
                    raise ValueError('response too large')
                rows = json.loads(data)
                if not isinstance(rows, list):
                    raise ValueError('unexpected response format')
                pages_read += 1
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    workflow = row.get('issue_state')
                    summary = {'state': row.get('state'), 'issue_state_type': type(workflow).__name__}
                    if isinstance(workflow, dict):
                        summary['workflow'] = {k: workflow.get(k) for k in ('title', 'name', 'state') if k in workflow}
                    counts[json.dumps(summary, ensure_ascii=False, sort_keys=True)] += 1
                if len(rows) < 50:
                    break
                if page == args.pages:
                    capped = True
        print(json.dumps({'pages_read': pages_read, 'bounded_sample': True, 'more_pages_possible': capped,
                          'states': [{'projection_input': json.loads(key), 'count': count} for key, count in sorted(counts.items())]}, ensure_ascii=False, indent=2))
        return 0
    except urllib.error.HTTPError as error:
        print('Gitee returned HTTP %s. No response body or credential was printed.' % error.code, file=sys.stderr)
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        print('Read failed: check network, permission, or response format. No credential or response body was printed.', file=sys.stderr)
    finally:
        token = ''
    return 1

if __name__ == '__main__':
    raise SystemExit(main())
