"""NFL Run/Pass Tendencies.

    python run.py update          download missing seasons, refresh the current one, rebuild plays
    python run.py update --all    re-download every season
    python run.py build           render the static site into site/
    python run.py serve           preview site/ at http://localhost:8000
"""
import argparse
import functools
import http.server

from runpass import build, data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["update", "build", "serve"])
    parser.add_argument("--all", action="store_true", help="update: re-download every season")
    parser.add_argument("--port", type=int, default=8000)
    args = parser.parse_args()

    if args.command == "update":
        data.update(all_seasons=args.all)
    elif args.command == "build":
        build.build()
    else:
        handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(build.SITE))
        print(f"Serving {build.SITE} at http://localhost:{args.port}")
        http.server.ThreadingHTTPServer(("", args.port), handler).serve_forever()


if __name__ == "__main__":
    main()
