import argparse
import json
import sys
from urllib.parse import parse_qs
from urllib.parse import urlencode


def create_arg_parser():
    ap = argparse.ArgumentParser()
    ap.add_argument('--names',
                    action='store',
                    dest='names',
                    nargs='+')
    ap.add_argument('--output',
                    action='store',
                    choices=['env', 'json', 'query_string'],
                    default='json',
                    dest='output',
                    nargs='?')
    return ap


def dump_env(d_names):
    for k, v in d_names.items():
        print(f'{k}="{v}"')


def dump_json(d_names):
    print(json.dumps(d_names, indent=3))


def dump_query_string(d_names):
    qs = urlencode(d_names)
    print(qs)


if __name__ == '__main__':
    qs = sys.stdin.readline()
    d = parse_qs(qs)
    ap = create_arg_parser()
    args = ap.parse_args()
    d_names = {k: ','.join(v) for k, v in d.items() if k in args.names}
    if args.output == 'env':
        dump_env(d_names)
    elif args.output == 'json':
        dump_json(d_names)
    elif args.output == 'query_string':
        dump_query_string(d_names)
    else:
        raise Exception(f'Unkwnon output format: {d_names.output}. This message should never happen. Weird!')

