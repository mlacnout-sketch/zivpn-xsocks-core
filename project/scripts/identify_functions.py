import re
import sys
import os

def identify_hysteria_functions(symbols_file):
    """
    Identify key Hysteria functions from symbol table
    """
    patterns = {
        'init': [
            r'.*[Ii]nit.*',
            r'.*[Ss]etup.*',
            r'.*[Cc]onfigure.*'
        ],
        'connection': [
            r'.*[Cc]onnect.*',
            r'.*[Dd]ial.*',
            r'.*[Hh]andshake.*'
        ],
        'transport': [
            r'.*[Ss]end.*',
            r'.*[Rr]eceive.*',
            r'.*[Ww]rite.*',
            r'.*[Rr]ead.*'
        ],
        'crypto': [
            r'.*[Ee]ncrypt.*',
            r'.*[Dd]ecrypt.*',
            r'.*[Aa]uth.*',
            r'.*[Ss]ign.*'
        ],
        'obfuscation': [
            r'.*[Oo]bfs.*',
            r'.*[Mm]ask.*',
            r'.*[Ss]cramble.*'
        ],
        'congestion': [
            r'.*[Cc]ongestion.*',
            r'.*[Bb]andwidth.*',
            r'.*[Rr]ate.*'
        ]
    }

    if not os.path.exists(symbols_file):
        print(f"Error: Symbols file {symbols_file} not found.")
        return {}

    with open(symbols_file, 'r') as f:
        symbols = f.readlines()

    categorized = {k: [] for k in patterns.keys()}

    for symbol in symbols:
        for category, pattern_list in patterns.items():
            for pattern in pattern_list:
                if re.search(pattern, symbol):
                    categorized[category].append(symbol.strip())
                    break

    # Print results
    for category, funcs in categorized.items():
        print(f"\n[{category.upper()}] Functions found: {len(funcs)}")
        for func in funcs[:10]:  # Show first 10
            print(f"  - {func}")

    return categorized

if __name__ == '__main__':
    if len(sys.argv) > 1:
        symbols_file = sys.argv[1]
    else:
        symbols_file = 'project/analysis/libuz_symbols.txt'

    symbols = identify_hysteria_functions(symbols_file)
