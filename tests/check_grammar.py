#!/usr/bin/env python3
"""Optional offline syntax check, NOT the Godot compiler or runtime.
Requires Python packages lark and regex. Run: python tests/check_grammar.py
The vendored grammar is transcribed from gdtoolkit 4.3.4 (MIT), retaining rules.
This small indenter supports the subset this project uses; multiline lambdas
inside parentheses are deliberately unsupported (none are used in this project).
Source: https://github.com/Scony/godot-gdscript-toolkit/tree/4.3.4/gdtoolkit/parser
"""
from pathlib import Path
import json
import hashlib
import sys
try:
    from lark import Lark
    from lark.indenter import Indenter
except ImportError:
    sys.exit('Optional grammar check needs lark and regex; native tests use Run Tests.bat.')

ROOT = Path(__file__).resolve().parents[1]
GRAMMAR = ROOT / 'tests/vendor/gdtoolkit/gdscript.lark'

class ProjectIndenter(Indenter):
    NL_type = '_NL'
    OPEN_PAREN_types = ['LPAR','LSQB','LBRACE']
    CLOSE_PAREN_types = ['RPAR','RSQB','RBRACE']
    INDENT_type = '_INDENT'
    DEDENT_type = '_DEDENT'
    tab_len = 4
    def handle_NL(self, token):
        for produced in super().handle_NL(token):
            yield produced
            if produced.type == self.DEDENT_type:
                yield token

def main():
    parser = Lark.open(str(GRAMMAR), parser='lalr', start='start',
                       postlex=ProjectIndenter(), maybe_placeholders=False,
                       propagate_positions=True, regex=True)
    results=[]
    for path in sorted(ROOT.rglob('*.gd')):
        if '.godot' in path.parts:
            continue
        result={'path':path.relative_to(ROOT).as_posix(),
                'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
        try:
            parser.parse(path.read_text(encoding='utf-8')+'\n')
            result['passed']=True
        except Exception as exc:
            result['passed']=False
            result['error']=str(exc)
        results.append(result)
        print(('GRAMMAR PASS: ' if result['passed'] else 'GRAMMAR FAIL: ')+result['path'])
        if not result['passed']: print(result['error'])
    # Check that obvious malformed syntax really gets rejected by this harness.
    negative_checks=[]
    for bad in ['extends Node\nfunc bad( -> void:\n\tpass\n',
                'extends Node\nfunc bad() -> void:\n\tvar value = [1, 2\n']:
        try:
            parser.parse(bad+'\n')
            negative_checks.append(False)
        except Exception:
            negative_checks.append(True)
    failed=sum(not x['passed'] for x in results)
    report={'scope':'Grammar only; no Godot API/type checking, compilation, or execution',
            'grammar_source':'gdtoolkit 4.3.4 grammar, transcribed from the published source',
            'indenter':'project subset adapter; no multiline lambdas inside parentheses',
            'grammar_sha256':hashlib.sha256(GRAMMAR.read_bytes()).hexdigest(),
            'passed':len(results)-failed,'failed':failed,
            'negative_syntax_controls_passed':all(negative_checks), 'files':results}
    (ROOT/'docs/grammar_check_results.json').write_text(json.dumps(report,indent=2)+'\n')
    print(f'GRAMMAR RESULT: {len(results)-failed} passed; {failed} failed. Native compilation not checked.')
    return int(failed>0 or not all(negative_checks))

if __name__ == '__main__':
    sys.exit(main())
