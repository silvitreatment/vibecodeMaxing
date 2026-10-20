#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
developer_directory="$(xcode-select -p)"
testing_frameworks="$developer_directory/Library/Developer/Frameworks"
if [[ -d "$testing_frameworks/Testing.framework" ]]; then
    swift test -Xswiftc "-F$testing_frameworks" \
        -Xlinker -rpath -Xlinker "$testing_frameworks" \
        -Xlinker -rpath -Xlinker "$developer_directory/Library/Developer/usr/lib"
else
    swift test
fi
