## Python

— use `uv`/`pdm`, never `pip`
- deps: `uv add` / `pdm add`; or import via `uv add -r` / `pdm import`
- run: `uv run` / `pdm run`, never activate venv
- one-off: `uvx <cli>`, `uv run --with <pkg>`
