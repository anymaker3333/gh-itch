#!/usr/bin/env python3
"""Audit translation packs against their English source.

Checks, per locale file:
  * parses as JSON
  * key set identical to English
  * key order identical to English
  * no empty values
  * no value equal to its own key
  * placeholders {..} multiset identical to the English value

Values identical to English are reported as review warnings, not failures:
proper nouns (game, city, street and route names) are legitimately shared.

Prints a per-file line and a summary. Exit code 1 on any structural failure.
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
I18N = ROOT / "data" / "i18n"
LOCALES = ["az", "be", "cs", "de", "fr", "pl", "ru", "uk", "zh_CN"]
PLACEHOLDER = re.compile(r"\{[^}]*\}")


def audit(game: str) -> tuple[list[str], list[str]]:
    problems: list[str] = []
    warnings: list[str] = []
    en_path = I18N / "en" / f"game_{game}.json"
    en = json.loads(en_path.read_text(encoding="utf-8"))
    en_keys = list(en.keys())
    for loc in LOCALES:
        path = I18N / loc / f"game_{game}.json"
        if not path.exists():
            problems.append(f"{loc}: MISSING FILE")
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except Exception as exc:  # noqa: BLE001
            problems.append(f"{loc}: invalid JSON ({exc})")
            continue
        if list(data.keys()) != en_keys:
            missing = [k for k in en_keys if k not in data]
            extra = [k for k in data if k not in en]
            problems.append(
                f"{loc}: key set/order mismatch (missing={len(missing)}, extra={len(extra)})"
            )
            continue
        same = 0
        for key, value in data.items():
            if not isinstance(value, str) or not value.strip():
                problems.append(f"{loc}: empty/non-string value for {key}")
                continue
            if value == key:
                problems.append(f"{loc}: value equals key for {key}")
            if sorted(PLACEHOLDER.findall(value)) != sorted(PLACEHOLDER.findall(en[key])):
                problems.append(
                    f"{loc}: placeholder mismatch for {key}: {value!r} vs {en[key]!r}"
                )
            if value == en[key] and len(en[key]) > 3:
                same += 1
        if same:
            warnings.append(f"{game}/{loc}: {same} values identical to English (proper nouns)")
        print(f"OK   {game:24} {loc:6} {len(data):3} keys")
    return problems, warnings


def main() -> int:
    games = sys.argv[1:] or sorted(
        p.stem.removeprefix("game_") for p in (I18N / "en").glob("game_*.json")
    )
    problems: list[str] = []
    warnings: list[str] = []
    for game in games:
        game_problems, game_warnings = audit(game)
        problems.extend(game_problems)
        warnings.extend(game_warnings)
    print()
    for warning in warnings:
        print(f"WARN {warning}")
    if problems:
        print(f"FAIL {len(problems)} problem(s):")
        for problem in problems:
            print(f"  • {problem}")
        return 1
    print(f"PASS all audited packs for {len(games)} game(s) ({len(warnings)} review warnings)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
