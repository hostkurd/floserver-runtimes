# FloServer runtimes

Portable builds of the programs [FloServer](https://floserver.org) runs on
**Linux and macOS** where their projects publish no ready-made build of their
own: PHP, nginx, and (to come) Apache, PostgreSQL, Valkey and MariaDB for macOS.
Windows builds come straight from each project.

Each runtime has a GitHub Actions workflow. Started by hand with a version,
it builds the runtime, runs a smoke test, and publishes a GitHub Release
tagged `<runtime>-<version>-<build>` with one archive per platform
(`<runtime>-<version>-<platform>.tar.gz`, platforms `linux-x64` and
`macos-arm64`) and its SHA-256. FloServer's Publisher takes the files from
the release, checks them, and adds them to FloServer's signed runtime list;
FloServer itself only downloads from that list.

| Folder | What |
|---|---|
| `sources.json` | Every source archive a build may use, with its SHA-256. A download that doesn't match is refused. |
| `php/` | The PHP extensions built in (always on) and built as `.so` files (switched per project). |
| `scripts/` | The build, smoke-test and packaging scripts the workflows run (they also run on a Linux or Mac machine). |
| `.github/workflows/` | One workflow per runtime. |

## Building a new version

1. Add the version and its SHA-256 (from the project's own announcement or
   checksum file) to `sources.json`, in a pull request.
2. After it's merged, open **Actions → the runtime's workflow → Run
   workflow**, give the version (and the platforms), and run it.
3. The release appears under **Releases**. Then use **Updates** in the
   FloServer Publisher as usual.

PHP is built with [static-php-cli](https://github.com/crazywhalecc/static-php-cli)
(the version pinned in `sources.json`): on Linux in its CentOS 7 container,
so one build runs on every glibc distribution FloServer supports.

static-php-cli downloads each library's newest release. Every file it
downloads is checked against `php/sources.lock.json` (php-src against
php.net's published SHA-256) before anything is built, so a library that
changes stops the build. Then run the **php** workflow with *update_lock*:
it opens a pull request with the new lock. Review the names and versions,
merge it, and run the workflow again. `php/pinned-sources.txt` fixes a
source to one address when the newest release isn't wanted (Xdebug, whose
newest is a pre-release).

Known gap: the build tools themselves (static-php-cli's CentOS 7 image and
the compilers and PHP it installs into it, or Homebrew on macOS) come from
their usual places without a pinned hash. They build the program but
aren't part of it.

## Licences

Each archive carries the licences of the program and of everything built
into it, in `licenses/`, and a `floserver-build.json` naming the versions
used. The scripts in this repository belong to HostKurd.
