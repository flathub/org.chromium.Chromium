#!/usr/bin/env nu

# https://github.com/nushell/nushell/pull/16015
# but simplified
def only [path?: cell-path]: [table -> any, list -> any] {
  if ($in | length) != 1 {
    print ($in | debug)
    error make { msg: "expected exactly one element" }
  } else if $path != null {
    $in | get 0 | get $path
  } else {
    $in | get 0
  }
}

def http [args: list<string>] {
  # Use a temporary file, so that curl can clear it on retries, and we don't end
  # up wih mixed output from previous attempts.
  let tmp = (mktemp)
  try {
    ^curl -Lf --retry 20 --speed-limit 100 --speed-time 5 -o $tmp ...$args
    open -r $tmp
  } finally {
    rm -f $tmp
  }
}

# finds a Python 'key': 'value' from a dict literal
def get-deps-dict-value [key: string] {
  $in | parse -r $"\(?m)^\\s*'($key)': '\(?<value>[^']+)'" | only value
}

# parses a node package-lock.json base64 integrity value and turns it into a
# more normal hex digest
def parse-node-sha512 [] {
  let parts = $in | parse '{alg}-{b64}' | only
  if $parts.alg != 'sha512' {
    error make { msg: $'unknown node integrity algorithm: ($parts.alg)' }
  }

  $parts.b64 | decode base64 | encode hex --lower
}

def parse-sha256-table [] {
  $in | split column -r '\s+' sha256 filename
}

def cipd-sha256 [p: string, v: string] {
  let data = ({package: $p, version: $v} | to json)
  let instance = (
    http [
      -H 'Content-Type: application/json' -H 'Accept: application/json'
      --data $data
      'https://chrome-infra-packages.appspot.com/prpc/cipd.Repository/ResolveVersion'
    ]
    | str replace -rm "^\\)\\]\\}'$" '' # strip the XSSI prefix
    | from json
    | get instance
  )

  if $instance.hashAlgo != 'SHA256' {
    error make { msg: $'unknown hashAlgo: ($instance.hashAlgo)' }
  }

  $instance.hexDigest
}

def gitiles-src [path: string] {
  http [$'($path)?format=TEXT'] | decode base64 | decode
}

def get-arm64-toolchain-release-url [
  release_prefix: string
  revision: string
  filename_prefix?: string
] {
  let release = (
    git ls-remote --tags https://github.com/refi64/cr-toolchain-arm64 $'($release_prefix)-($revision)-*'
    | lines
    | parse -r '^\S+\s+refs/tags/(?<release>\S+)$'
    | sort -n
    | last -s
    | get release
  )

  mut filename = $'($release).tar.xz'
  if $filename_prefix != null {
    $filename = $filename | str replace -r $'^($release_prefix)' $filename_prefix
  }

  $'https://github.com/refi64/cr-toolchain-arm64/releases/download/($release)/($filename)'
}

def is-gha [] {
  'GITHUB_OUTPUT' in $env
}

def github-output [line: string] {
  if (is-gha) {
    $'($line)(char eol)' | save -a $env.GITHUB_OUTPUT
  }
}

def main [--commit] {
  const manifest = path self ../org.chromium.Chromium.yaml
  const metainfo = path self ../org.chromium.Chromium.metainfo.xml

  let release_info = (
    http ['https://chromiumdash.appspot.com/fetch_releases?platform=Linux&channel=Stable&num=1']
    | from json
    | only
  )
  # let chromium_version = $release_info | get version
  let chromium_version = '154.0.8037.97'
  let chromium_time = ($release_info | get time) // 1000 | into datetime -f '%s' -z UTC
  print $'Chromium version: ($chromium_version), released on: ($chromium_time)'
  github-output $'chromium-version=($chromium_version)'

  let chromium_url = $'https://github.com/chromium-linux-tarballs/chromium-tarballs/releases/download/($chromium_version)/chromium-($chromium_version)-linux.tar.xz'
  try {
    http ['--head' $chromium_url]
  } catch {|e|
    let exit = ($e | get -o exit_code)
    if $exit != 22 {  # 22: HTTP error from -f
      error make $e  # rethrow
    }

    if (is-gha) {
      print $'::warning:: Chromium tarball is not yet available'
    } else {
      print -e 'Chromium tarball is not yet available'
    }
    exit 1
  }

  let chromium_sha256 = (
    http [$'($chromium_url).hashes']
    | lines
    | split column -r '\s+' alg digest
    | where alg == 'sha256'
    | only digest
  )

  print $'Chromium tarball: ($chromium_url) ($chromium_sha256)'

  let websrc = $'https://chromium.googlesource.com/chromium/src/+/($chromium_version)'

  let clang_build_py = gitiles-src $'($websrc)/tools/clang/scripts/build.py'
  let cmake_ver = $clang_build_py | parse -r "'cmake-(?<value>[0-9.]+)-linux-x86_64'" | only value
  let cmake_sha256_table = (
    http [$'https://github.com/Kitware/CMake/releases/download/v($cmake_ver)/cmake-($cmake_ver)-SHA-256.txt']
    | lines | parse-sha256-table
  )
  let cmake_x64_url = $'https://github.com/Kitware/CMake/releases/download/v($cmake_ver)/cmake-($cmake_ver)-linux-x86_64.tar.gz'
  let cmake_x64_sha256 = ($cmake_sha256_table | where filename == ($cmake_x64_url | path basename) | only sha256)
  let cmake_arm64_url = $'https://github.com/Kitware/CMake/releases/download/v($cmake_ver)/cmake-($cmake_ver)-linux-aarch64.tar.gz'
  let cmake_arm64_sha256 = ($cmake_sha256_table | where filename == ($cmake_arm64_url | path basename) | only sha256)
  print $'CMake x64: ($cmake_x64_url) ($cmake_x64_sha256)'
  print $'CMake arm64: ($cmake_arm64_url) ($cmake_arm64_sha256)'

  let clang_update_py = gitiles-src $'($websrc)/tools/clang/scripts/update.py'
  let llvm_revision = $clang_update_py | parse -r "(?m)^CLANG_REVISION = '(?<value>[^']+)'" | only value
  let llvm_sub_revision = $clang_update_py | parse -r '(?m)^CLANG_SUB_REVISION = (?<value>.+)' | only value
  print $'LLVM: ($llvm_revision)-($llvm_sub_revision)'
  let llvm_prebuilt_x64_url = $'https://commondatastorage.googleapis.com/chromium-browser-clang/Linux_x64/clang-($llvm_revision)-($llvm_sub_revision).tar.xz'
  let llvm_prebuilt_x64_sha256 = http [$llvm_prebuilt_x64_url] | hash sha256
  print $'LLVM x64: ($llvm_prebuilt_x64_url) ($llvm_prebuilt_x64_sha256)'
  let llvm_prebuilt_arm64_url = get-arm64-toolchain-release-url 'clang' $'($llvm_revision)-($llvm_sub_revision)'
  let llvm_prebuilt_arm64_sha256 = http [$'($llvm_prebuilt_arm64_url).sha256'] | lines | parse-sha256-table | only sha256
  print $'LLVM arm64: ($llvm_prebuilt_arm64_url) ($llvm_prebuilt_arm64_sha256)'
  let clang_format_arm64_url = $llvm_prebuilt_arm64_url | str replace -r '/clang-([^/]+)$' '/clang-format-${1}'
  let clang_format_arm64_sha256 = http [$'($clang_format_arm64_url).sha256'] | lines | parse-sha256-table | only sha256
  print $'Clang format arm64: ($clang_format_arm64_url) ($clang_format_arm64_sha256)'

  let rust_update_py = gitiles-src $'($websrc)/tools/rust/update_rust.py'
  let rust_revision = $rust_update_py | parse -r "(?m)^RUST_REVISION = '(?<value>[^']+)'" | only value
  let rust_sub_revision = $rust_update_py | parse -r "(?m)^RUST_SUB_REVISION = (?<value>.+)" | only value
  print $'Rust: ($rust_revision)-($rust_sub_revision)-($llvm_revision)'
  let rust_prebuilt_x64_url = $'https://commondatastorage.googleapis.com/chromium-browser-clang/Linux_x64/rust-toolchain-($rust_revision)-($rust_sub_revision)-($llvm_revision).tar.xz'
  let rust_prebuilt_x64_sha256 = http [$rust_prebuilt_x64_url] | hash sha256
  print $'Rust x64: ($rust_prebuilt_x64_url) ($rust_prebuilt_x64_sha256)'
  let rust_prebuilt_arm64_url = get-arm64-toolchain-release-url 'rust' $'($rust_revision)-($rust_sub_revision)-($llvm_revision)' 'rust-toolchain'
  let rust_prebuilt_arm64_sha256 = http [$'($rust_prebuilt_arm64_url).sha256'] | lines | parse-sha256-table | only sha256
  print $'Rust arm64: ($rust_prebuilt_arm64_url) ($rust_prebuilt_arm64_sha256)'

  let ts_3pp = gitiles-src $'($websrc)/third_party/typescript/linux-amd64/3pp/3pp.pb'
  let ts_arm64_url = (
    $ts_3pp
    | parse -r '(?m)^\s*download_url: "(?<url>[^"]+)"'
    | only url
    | str replace -ar '\bx64\b' 'arm64'
  )
  let ts_arm64_sha256 = http [$ts_arm64_url] | hash sha256
  print $'TypeScript arm64: ($ts_arm64_url) ($ts_arm64_sha256)'

  let gclient_deps = gitiles-src $'($websrc)/DEPS'

  let devtools_frontend_revision = $gclient_deps | get-deps-dict-value devtools_frontend_revision
  print $'Devtools frontend revision: ($devtools_frontend_revision)'

  let devtools_package_lock = (
    gitiles-src $'https://chromium.googlesource.com/devtools/devtools-frontend/+/($devtools_frontend_revision)/package-lock.json'
    | from json
  )
  let esbuild_x64_url = $devtools_package_lock.packages.'node_modules/@esbuild/linux-x64'.resolved
  let esbuild_x64_sha512 = (
    $devtools_package_lock.packages.'node_modules/@esbuild/linux-x64'.integrity
    | parse-node-sha512
  )
  let esbuild_arm64_url = $devtools_package_lock.packages.'node_modules/@esbuild/linux-arm64'.resolved
  let esbuild_arm64_sha512 = (
    $devtools_package_lock.packages.'node_modules/@esbuild/linux-arm64'.integrity
    | parse-node-sha512
  )
  let rollup_arm64_url = $devtools_package_lock.packages.'node_modules/@rollup/rollup-linux-arm64-gnu'.resolved
  let rollup_arm64_sha512 = (
    $devtools_package_lock.packages.'node_modules/@rollup/rollup-linux-arm64-gnu'.integrity
    | parse-node-sha512
  )

  print $'esbuild x64: ($esbuild_x64_url) ($esbuild_x64_sha512)'
  print $'esbuild arm64: ($esbuild_arm64_url) ($esbuild_arm64_sha512)'
  print $'rollup arm64: ($rollup_arm64_url) ($rollup_arm64_sha512)'

  let dawn_revision = $gclient_deps | get-deps-dict-value dawn_revision
  print $'Dawn revision: ($dawn_revision)'

  let dawnsrc = $'https://dawn.googlesource.com/dawn/+/($dawn_revision)'
  let dawn_gclient_deps = gitiles-src $'($dawnsrc)/DEPS'
  let dawn_go_version = $dawn_gclient_deps | get-deps-dict-value dawn_go_version
  print $'Dawn Go version: ($dawn_go_version)'
  let dawn_go_x64_url = $'https://chrome-infra-packages.appspot.com/dl/infra/3pp/tools/go/linux-amd64/+/($dawn_go_version)'
  let dawn_go_x64_sha256 = cipd-sha256 infra/3pp/tools/go/linux-amd64 $dawn_go_version
  let dawn_go_arm64_url = $'https://chrome-infra-packages.appspot.com/dl/infra/3pp/tools/go/linux-arm64/+/($dawn_go_version)'
  let dawn_go_arm64_sha256 = cipd-sha256 infra/3pp/tools/go/linux-arm64 $dawn_go_version

  print $'Dawn Go x64: ($dawn_go_x64_url) ($dawn_go_x64_sha256)'
  print $'Dawn Go arm64: ($dawn_go_arm64_url) ($dawn_go_arm64_sha256)'

  let yaml = $'x-version-data:
  - &chromium_url ($chromium_url)
  - &chromium_sha256 ($chromium_sha256)
  - &cmake_x64_url ($cmake_x64_url)
  - &cmake_x64_sha256 ($cmake_x64_sha256)
  - &cmake_arm64_url ($cmake_arm64_url)
  - &cmake_arm64_sha256 ($cmake_arm64_sha256)
  - &llvm_prebuilt_x64_url ($llvm_prebuilt_x64_url)
  - &llvm_prebuilt_x64_sha256 ($llvm_prebuilt_x64_sha256)
  - &llvm_prebuilt_arm64_url ($llvm_prebuilt_arm64_url)
  - &llvm_prebuilt_arm64_sha256 ($llvm_prebuilt_arm64_sha256)
  - &clang_format_arm64_url ($clang_format_arm64_url)
  - &clang_format_arm64_sha256 ($clang_format_arm64_sha256)
  - &rust_prebuilt_x64_url ($rust_prebuilt_x64_url)
  - &rust_prebuilt_x64_sha256 ($rust_prebuilt_x64_sha256)
  - &rust_prebuilt_arm64_url ($rust_prebuilt_arm64_url)
  - &rust_prebuilt_arm64_sha256 ($rust_prebuilt_arm64_sha256)
  - &ts_arm64_url ($ts_arm64_url)
  - &ts_arm64_sha256 ($ts_arm64_sha256)
  - &esbuild_x64_url ($esbuild_x64_url)
  - &esbuild_x64_sha512 ($esbuild_x64_sha512)
  - &esbuild_arm64_url ($esbuild_arm64_url)
  - &esbuild_arm64_sha512 ($esbuild_arm64_sha512)
  - &rollup_arm64_url ($rollup_arm64_url)
  - &rollup_arm64_sha512 ($rollup_arm64_sha512)
  - &dawn_go_x64_url ($dawn_go_x64_url)
  - &dawn_go_x64_sha256 ($dawn_go_x64_sha256)
  - &dawn_go_arm64_url ($dawn_go_arm64_url)
  - &dawn_go_arm64_sha256 ($dawn_go_arm64_sha256)
'

  let updated_manifest = (
    open -r $manifest
    | decode
    | str replace -rmn '^x-version-data:\n(?: +[^\n]+\n)+' $yaml
  )

  let manifest_tmp = $'($manifest).tmp'
  $updated_manifest | save -f $manifest_tmp
  let has_manifest_diff = try {
    diff -u $manifest $manifest_tmp
    false
  } catch {
    true
  }

  if not $has_manifest_diff {
    rm $manifest_tmp
  }

  let metainfo_tmp = $'($metainfo).tmp'
  let current_metainfo = open -r $metainfo | decode
  let has_metainfo_diff = if not ($current_metainfo
    | str contains $'<release version="($chromium_version)"') {
    let now = $chromium_time | format date "%Y-%m-%d"
    let release = $'
    <release version="($chromium_version)" date="($now)">
      <description/>
    </release>
'
    $current_metainfo | str replace -rmn "(?<=^\\s+<releases>)\n" $release | save -f $metainfo_tmp
    do -i { diff -u $metainfo $metainfo_tmp }
    true
  } else {
    false
  }

  if not ($has_manifest_diff or $has_metainfo_diff) {
    print 'Nothing to do.'
    exit
  }

  if $has_manifest_diff {
    mv $manifest_tmp $manifest
  }

  if $has_metainfo_diff {
    mv $metainfo_tmp $metainfo
  }

  github-output 'changed=yes'

  if $commit {
    git commit -am $'Updates for Chromium ($chromium_version)'
    github-output $'short-tree=(git rev-parse --short 'HEAD^{tree}' | str trim)'
  }
}
