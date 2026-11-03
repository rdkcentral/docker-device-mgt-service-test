#!/usr/bin/env python3
"""Generate a module-independent Markdown L2 report from lcov and test inventories."""

import argparse
import datetime
from pathlib import Path
import re


def _pct(hit, found):
    return f'{hit / found * 100:.1f}%' if found else 'N/A'


def _strip_c(code):
    pattern = r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    return re.sub(pattern, ' ', code, flags=re.S)


def _c_function_names(path):
    text = _strip_c(path.read_text(encoding='utf-8', errors='replace'))
    names, depth, buffer = set(), 0, ''
    keywords = {'if', 'while', 'for', 'switch', 'else', 'return', 'sizeof', 'do'}
    for line in text.splitlines():
        if line.strip().startswith('#'):
            continue
        for char in line:
            if char == '{':
                if depth == 0:
                    match = re.search(r'([A-Za-z_]\w*)\s*\([^;{}]*\)\s*$', buffer)
                    if match and match.group(1) not in keywords:
                        names.add(match.group(1))
                    buffer = ''
                depth += 1
            elif char == '}':
                depth -= 1
                if depth == 0:
                    buffer = ''
            elif depth == 0:
                buffer = '' if char == ';' else buffer + char
        if depth == 0:
            buffer += ' '
    return names


def scan_source_functions(src_dir):
    root = Path(src_dir)
    return {
        path.relative_to(root).as_posix(): _c_function_names(path)
        for path in sorted(root.rglob('*.c')) if path.is_file()
    }


def _source_name(source, src_dir, source_names):
    source = source.replace('\\', '/')
    root = Path(src_dir).resolve().as_posix()
    if source.startswith(root + '/'):
        relative = source[len(root) + 1:]
        if relative in source_names:
            return relative
    candidates = [name for name in source_names
                  if source == name or source.endswith('/' + name)]
    if not candidates:
        candidates = [name for name in source_names
                      if Path(name).name == source.rsplit('/', 1)[-1]]
    return candidates[0] if len(candidates) == 1 else None


def parse_tracefile(path, src_dir, source_names):
    files = {}
    current = None
    with open(path, encoding='utf-8') as tracefile:
        for raw in tracefile:
            line = raw.rstrip()
            if line.startswith('SF:'):
                name = _source_name(line[3:], src_dir, source_names)
                current = {'name': name, 'lh': 0, 'lf': 0, 'hit': set()}
            elif line == 'end_of_record' and current is not None:
                name = current['name']
                if name is not None:
                    if name in files:
                        raise ValueError(f'Duplicate lcov record for {name}; merge tracefiles with lcov first')
                    files[name] = current
                current = None
            elif current is not None:
                if line.startswith('LH:'):
                    current['lh'] = int(line[3:])
                elif line.startswith('LF:'):
                    current['lf'] = int(line[3:])
                elif line.startswith('FNDA:'):
                    count, _, name = line[5:].partition(',')
                    if int(count) > 0:
                        current['hit'].add(name)
    return files


def scan_features(features_dir):
    root = Path(features_dir)
    return {
        path.relative_to(root).as_posix(): len(re.findall(
            r'^\s*Scenario(?:\s+Outline)?:',
            path.read_text(encoding='utf-8', errors='replace'), re.M))
        for path in sorted(root.rglob('*.feature')) if path.is_file()
    }


def scan_tests(tests_dir):
    root = Path(tests_dir)
    tests = {}
    disabled_functions = disabled_files = 0
    for path in sorted(root.rglob('test_*.py')):
        if not path.is_file():
            continue
        text = path.read_text(encoding='utf-8', errors='replace')
        active = len(re.findall(r'^\s*(?:async\s+)?def test_', text, re.M))
        skipped = len(re.findall(
            r'^\s*@pytest\.mark\.skip\b(?:\([^\n]*\))?[^\n]*\n'
            r'(?:\s*@(?!pytest\.mark\.skip)[^\n]*\n)*\s*(?:async\s+)?def test_', text, re.M))
        commented = len(re.findall(r'^\s*#\s*(?:async\s+)?def test_', text, re.M))
        tests[path.relative_to(root).as_posix()] = active
        disabled_functions += skipped + commented
        if active == skipped:
            disabled_files += 1
    return tests, disabled_functions, disabled_files


def build_mapping(features, tests):
    unmatched = set(tests)
    pairs = []
    for feature, scenarios in features.items():
        path = Path(feature)
        stem = path.stem
        candidate = path.with_name(
            (stem if stem.startswith('test_') else 'test_' + stem) + '.py').as_posix()
        test = candidate if candidate in tests else None
        pairs.append((feature, scenarios, test, tests.get(test, 0)))
        unmatched.discard(test)
    return pairs, {name: tests[name] for name in sorted(unmatched)}


def generate(component, src_dir, features_dir, tests_dir, sources, files,
             features, tests, disabled_functions, disabled_files):
    pairs, orphan_tests = build_mapping(features, tests)
    functions_found = sum(len(names) for names in sources.values())
    functions_hit = sum(len(names & files.get(name, {}).get('hit', set()))
                        for name, names in sources.items())
    lines_hit = sum(data['lh'] for data in files.values())
    lines_found = sum(data['lf'] for data in files.values())
    mapped = sum(test is not None for _, _, test, _ in pairs)
    lines = [
        f'# {component} L2 Coverage Report', '',
        f'**Generated:** {datetime.date.today().isoformat()}  ',
        f'**Component:** `{component}`  ',
        f'**Source directory:** `{src_dir}`  ',
        f'**Features:** `{features_dir}`  ',
        f'**Tests:** `{tests_dir}`  ',
        '**Coverage tool:** lcov', '',
        '## 1. Executive Summary', '',
        '| Metric | Value |', '|---|:---:|',
        f'| Feature files | {len(features)} |',
        f'| Feature scenarios | {sum(features.values())} |',
        f'| Pytest files | {len(tests)} |',
        f'| Test functions (`test_*`, including skipped) | {sum(tests.values())} |',
        f'| Disabled test functions (skip markers or commented definitions) | {disabled_functions} |',
        f'| Files with no enabled test functions | {disabled_files} |',
        f'| Mapped feature/test pairs | {mapped} / {len(features)} |',
        f'| Unmatched test files | {len(orphan_tests)} |',
        f'| Line coverage (lcov) | {_pct(lines_hit, lines_found)} ({lines_hit} of {lines_found} lines) |',
        f'| Source functions found | {functions_found} |',
        f'| Functions hit | {functions_hit} |',
        f'| Functions not hit | {functions_found - functions_hit} |',
        f'| Current functional coverage | {_pct(functions_hit, functions_found)} |', '',
        '> Function coverage compares lcov FNDA counts with a heuristic scan of C function',
        '> definitions under the source directory, including preprocessor branches.',
        '> Test counts are a static inventory, not pass/fail results. Skip counts are',
        '> estimates; conditional, class-level and module-level skips are not evaluated.', '',
        '## 2. Feature-to-Test Mapping', '',
        '| Feature File | Scenarios | Test File | Tests | Status |',
        '|---|:---:|---|:---:|---|',
    ]
    for feature, scenarios, test, count in pairs:
        status = 'Missing test file' if test is None else (
            f'GAP ({scenarios - count} missing)' if count < scenarios else 'Count sufficient')
        lines.append(f'| `{feature}` | {scenarios} | {test or "-"} | {count} | {status} |')
    lines += ['', '> Matching uses the same relative directory and feature stem, with an optional',
              '> test_ prefix. Scenario Outline rows and parametrized cases are not expanded.',
              '', '### Unmatched Test Files', '', '| Test File | Tests |', '|---|:---:|']
    for test, count in orphan_tests.items():
        lines.append(f'| `{test}` | {count} |')
    lines += ['', '## 3. Source Module Coverage (lcov)', '',
              '| Module | Lines | Functions |', '|---|:---:|:---:|']
    for name, functions in sources.items():
        data = files.get(name)
        if data is None:
            lines.append(f'| `{name}` | no data | 0/{len(functions)} |')
        else:
            hit = len(functions & data['hit'])
            lines.append(f'| `{name}` | {_pct(data["lh"], data["lf"])} '
                         f'({data["lh"]}/{data["lf"]}) | {_pct(hit, len(functions))} '
                         f'({hit}/{len(functions)}) |')
    lines += ['', '> Only trace records matched to source files in this module contribute to line coverage.',
              '> Ambiguous source paths are excluded; keep source-relative paths in the tracefile.',
              '', '## 4. Scenario-to-Test Gap Analysis', '']
    gaps = [(feature, scenarios, test, count) for feature, scenarios, test, count in pairs
            if test is None or count < scenarios]
    if gaps:
        lines += ['| Feature File | Scenarios | Tests | Missing |', '|---|:---:|:---:|:---:|']
        for feature, scenarios, test, count in gaps:
            lines.append(f'| `{feature}` | {scenarios} | {count} | {max(0, scenarios - count)} |')
    else:
        lines.append('No scenario-to-test count gaps found.')
    lines += ['', '> Counts alone do not prove behavior coverage. Module-specific behavior analysis',
              '> and recommendations belong in the module documentation.', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tracefile', required=True, type=Path)
    parser.add_argument('--src-dir', required=True, type=Path)
    parser.add_argument('--features-dir', required=True, type=Path)
    parser.add_argument('--tests-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--component', help='Report name (default: parent of the source directory)')
    args = parser.parse_args()
    for name in ('src_dir', 'features_dir', 'tests_dir'):
        if not getattr(args, name).is_dir():
            parser.error(f'Not a directory: {getattr(args, name)}')
    try:
        sources = scan_source_functions(args.src_dir)
        files = parse_tracefile(args.tracefile, args.src_dir, sources)
        features = scan_features(args.features_dir)
        tests, disabled_functions, disabled_files = scan_tests(args.tests_dir)
        report = generate(
            args.component or args.src_dir.resolve().parent.name,
            args.src_dir, args.features_dir, args.tests_dir, sources, files,
            features, tests, disabled_functions, disabled_files)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding='utf-8')
    except (OSError, ValueError) as error:
        parser.exit(1, f'Error: {error}\n')
    print(f'Written: {args.output}')


if __name__ == '__main__':
    main()