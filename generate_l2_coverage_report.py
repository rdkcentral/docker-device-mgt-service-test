#!/usr/bin/env python3
"""Generate a module-independent Markdown L2 report from lcov and test inventories."""

import argparse
import datetime
import json
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
                current = {'name': name, 'lh': 0, 'lf': 0, 'hit': set(),
                           'fnh': None, 'fnf': None}
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
                elif line.startswith('FNH:'):
                    current['fnh'] = int(line[4:])
                elif line.startswith('FNF:'):
                    current['fnf'] = int(line[4:])                    
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


def load_report_details(path):
    details = json.loads(Path(path).read_text(encoding='utf-8'))
    string_fields = {'component_id', 'source_label', 'test_suite', 'target_coverage'}
    list_fields = {'source_order', 'behavior_detail', 'recommendations', 'infrastructure_notes'}
    if not isinstance(details, dict):
        raise ValueError('Report details must be a JSON object')
    for key, value in details.items():
        if key in string_fields and isinstance(value, str):
            continue
        if key in list_fields and isinstance(value, list) and all(
                isinstance(line, str) for line in value):
            continue
        raise ValueError(f'Unknown report details field or invalid value: {key}')
    return details


def _bar(hit, found, width=20):
    filled = round(hit / found * width) if found else 0
    return '\u2588' * filled + '\u2591' * (width - filled)


def generate(component, src_dir, features_dir, tests_dir, sources, files,
             features, tests, disabled_functions, disabled_files, details=None):
    details = details or {}
    pairs, orphan_tests = build_mapping(features, tests)
    orphan_features = [(feature, scenarios) for feature, scenarios, test, _ in pairs
                       if test is None]
    mapped_pairs = [pair for pair in pairs if pair[2] is not None]
    functions_found = sum(len(names) for names in sources.values())
    functions_hit = sum(len(names & files.get(name, {}).get('hit', set()))
                        for name, names in sources.items())
    lines_hit = sum(data['lh'] for data in files.values())
    lines_found = sum(data['lf'] for data in files.values())
    compiled_coverage = 'N/A (FNH/FNF unavailable)'
    if files and all(data.get('fnh') is not None and data.get('fnf') is not None
                     for data in files.values()):
        compiled_hit = sum(data['fnh'] for data in files.values())
        compiled_found = sum(data['fnf'] for data in files.values())
        compiled_coverage = f'{_pct(compiled_hit, compiled_found)} ({compiled_hit}/{compiled_found} functions)'                 
    mapped = sum(test is not None for _, _, test, _ in pairs)
    source_label = details.get('source_label', Path(src_dir).as_posix()).rstrip('/\\')
    source_pattern = source_label + ('/**/*.c' if any('/' in name for name in sources) else '/*.c')
    lines = [
        f'# {component} L2 Coverage Report', '',
        f'**Generated:** {datetime.date.today().isoformat()}  ',
        f'**Component:** `{details.get("component_id", component)}` '
        f'(`{details.get("source_label", str(src_dir))}`)  ',
        f'**Test suite:** `{details.get("test_suite", str(tests_dir))}`  ',
        '**Coverage tool:** lcov (source-level instrumentation via `--coverage`)', '',
        '---', '',
        '## 1. Executive Summary', '',
        '**L2 Test Coverage**', '', '| Metric | Value |', '|---|:---:|',
        f'| Source functions found | {functions_found} |',
        f'| Functions hit | {functions_hit} |',
        f'| Functions not hit | {functions_found - functions_hit} |',
        f'| Current functional coverage | {_pct(functions_hit, functions_found)} |',
        f'| Compiled-function coverage (lcov) | {compiled_coverage} |',        
        f'| Target L2 functional coverage | {details.get("target_coverage", "~100%")} |', '',
        '> Function coverage = functions called at least once during the L2 run (lcov `FNDA` > 0),',
        f'> divided by all function definitions in `{source_pattern}`, including those compiled out by `#if`.', '',
        '> Compiled-function coverage (lcov) = sum of FNH / sum of FNF for matched module files.',
        '> This measures compiled functions recorded by lcov, excluding compiled-out definitions.', '',        
        '**L2 Test Summary**', '',
        '| Metric | Value |', '|---|:---:|',
        f'| Feature files | {len(features)} |',
        f'| Feature scenarios | {sum(features.values())} |',
        f'| Pytest files | {len(tests)} |',
        f'| Test functions (`test_*`) | {sum(tests.values())} |',
        f'| Mapped feature/test pairs | {mapped} / {len(features)} |',
        f'| Unmatched test files | {len(orphan_tests)} |',
        f'| Line coverage (lcov) | {_pct(lines_hit, lines_found)} ({lines_hit} of {lines_found} lines) |', '',
        '> Function definitions are discovered with a heuristic C source scan.',
        f'> Disabled test functions (skip markers or commented definitions): {disabled_functions};',
        f'> files with no enabled test functions: {disabled_files}.',
        '> Test counts include skipped definitions and are not pass/fail results. Skip counts are',
        '> estimates; conditional, class-level and module-level skips are not evaluated.', '',
        '---', '', '## 2. Feature \u2194 Test Mapping', '',
        '### 2.1 Mapped Pairs', '',
        '| # | Feature File | Scenarios | Test File | Tests | Status |',
        '|:---:|---|:---:|---|:---:|:---:|',
    ]
    for index, (feature, scenarios, test, count) in enumerate(mapped_pairs, 1):
        status = f'**GAP** ({scenarios - count} missing)' if count < scenarios else 'PASS'
        lines.append(f'| {index} | `{feature}` | {scenarios} | `{test}` | {count} | {status} |')
    lines += [f'| | **Totals** | **{sum(pair[1] for pair in mapped_pairs)}** | | '
              f'**{sum(pair[3] for pair in mapped_pairs)}** | |', '',
              '> PASS means the test-definition count meets the scenario count, not that tests passed.',
              '> Matching uses the same relative directory and feature stem, with an optional',
              '> test_ prefix. Scenario Outline rows and parametrized cases are not expanded.', '']
    over_pairs = [pair for pair in mapped_pairs if pair[3] > pair[1]]
    lines += ['### 2.2 Tests Exceeding Scenario Count', '',
              '> Extra functions can include setup/teardown split more granularly than feature scenarios.', '',
              '| Feature File | Scenarios | Test File | Tests | Extra |',
              '|---|:---:|---|:---:|:---:|']
    for feature, scenarios, test, count in over_pairs:
        lines.append(f'| `{feature}` | {scenarios} | `{test}` | {count} | +{count - scenarios} |')
    lines += ['', '### 2.3 Orphan Tests (test exists, no feature file)', '',
              '| Test File | Tests | Note |', '|---|:---:|---|']
    for test, count in orphan_tests.items():
        lines.append(f'| `{test}` | {count} | **Missing `.feature` file** |')
    lines += ['', '### 2.4 Orphan Features (feature exists, no test file)', '',
              '| Feature File | Scenarios | Note |', '|---|:---:|---|']
    for feature, scenarios in orphan_features:
        lines.append(f'| `{feature}` | {scenarios} | **Missing test file** |')
    lines += ['', '---', '', '## 3. Source Module Coverage (lcov)', '',
              '| Module | Lines | Functions | Coverage Bar |', '|---|:---:|:---:|---|']
    source_order = list(dict.fromkeys(details.get('source_order', []) + sorted(sources)))
    for name in source_order:
        if name not in sources:
            continue
        functions = sources[name]
        data = files.get(name)
        if data is None:
            lines.append(f'| `{name}` | \u2014 | \u2014 | no data |')
        else:
            hit = len(functions & data['hit'])
            lines.append(f'| `{name}` | {_pct(data["lh"], data["lf"])} '
                         f'({data["lh"]}/{data["lf"]}) | {_pct(hit, len(functions))} '
                         f'({hit}/{len(functions)}) | `{_bar(data["lh"], data["lf"])}` |')
    lines += ['', '> Only trace records matched to source files in this module contribute to line coverage.',
              '> Ambiguous source paths are excluded; keep source-relative paths in the tracefile.',
              '', '---', '', '## 4. Per-Behavior Coverage Detail', '',
              '> Module-supplied assessment; not inferred from lcov or test counts.', '']
    lines += details.get('behavior_detail') or ['No module-specific behavior assessment supplied.']
    lines += ['', '---', '', '## 5. Scenario-to-Test Gap Analysis', '']
    gaps = [pair for pair in mapped_pairs if pair[3] < pair[1]]
    if gaps:
        lines += ['| Feature File | Scenarios | Tests | Missing |', '|---|:---:|:---:|:---:|']
        for feature, scenarios, test, count in gaps:
            lines.append(f'| `{feature}` | {scenarios} | {count} | **{scenarios - count}** |')
    else:
        lines.append('All mapped feature files have sufficient test function coverage.')
    if orphan_tests:
        lines += ['', '**Orphan tests** (no feature file):', '']
        lines += [f'- `{test}`' for test in orphan_tests]
    lines += ['', '> Unmatched features are listed in section 2.4; counts alone do not prove behavior coverage.',
              '', '---', '', '## 6. Gap Recommendations', '',
              '> Module-supplied recommendations; review when the implementation or tests change.', '']
    lines += details.get('recommendations') or ['No module-specific recommendations supplied.']
    lines += ['', '---', '', '## 7. Test Infrastructure Notes', '']
    lines += details.get('infrastructure_notes') or ['No module-specific infrastructure notes supplied.']
    lines += ['', '---', '', '## 8. Appendix: File Inventory', '',
              '### Feature Files', '', '| # | File | Scenarios |', '|:---:|---|:---:|']
    for index, (feature, scenarios) in enumerate(features.items(), 1):
        lines.append(f'| {index} | `{feature}` | {scenarios} |')
    lines += [f'| | **Total** | **{sum(features.values())}** |', '',
              '### Test Files', '', '| # | File | Tests |', '|:---:|---|:---:|']
    for index, (test, count) in enumerate(sorted(tests.items()), 1):
        lines.append(f'| {index} | `{test}` | {count} |')
    lines += [f'| | **Total** | **{sum(tests.values())}** |', '']
    return '\n'.join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tracefile', required=True, type=Path)
    parser.add_argument('--src-dir', required=True, type=Path)
    parser.add_argument('--features-dir', required=True, type=Path)
    parser.add_argument('--tests-dir', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--component', help='Report name (default: parent of the source directory)')
    parser.add_argument('--report-details', type=Path,
                        help='Module-owned JSON metadata and Markdown lines for sections 4, 6 and 7')
    args = parser.parse_args()
    for name in ('src_dir', 'features_dir', 'tests_dir'):
        if not getattr(args, name).is_dir():
            parser.error(f'Not a directory: {getattr(args, name)}')
    try:
        details = load_report_details(args.report_details) if args.report_details else None
        sources = scan_source_functions(args.src_dir)
        files = parse_tracefile(args.tracefile, args.src_dir, sources)
        features = scan_features(args.features_dir)
        tests, disabled_functions, disabled_files = scan_tests(args.tests_dir)
        report = generate(
            args.component or args.src_dir.resolve().parent.name,
            args.src_dir, args.features_dir, args.tests_dir, sources, files,
            features, tests, disabled_functions, disabled_files, details)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(report, encoding='utf-8')
    except (OSError, ValueError) as error:
        parser.exit(1, f'Error: {error}\n')
    print(f'Written: {args.output}')


if __name__ == '__main__':
    main()
