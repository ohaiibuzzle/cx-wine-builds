#!/usr/bin/env python3
"""Makes an installed Wine prefix self-contained and relocatable.

Copies every non-system dylib the install needs out of Homebrew into
PREFIX/lib, rewrites all references to @rpath/<name>, and gives each Mach-O
an rpath that points at PREFIX/lib relative to itself.

Two kinds of dependencies are handled:
  * linked ones, found with `otool -L`;
  * ones Wine's unix modules dlopen() by leaf name (libfreetype.6.dylib,
    libMoltenVK.dylib, ...). dyld resolves a leaf-name dlopen() as
    @rpath/<name> against the *calling* image's rpaths, so giving the unix
    modules an rpath to PREFIX/lib is enough for those to be found.

Modified files are ad-hoc re-signed (the x86_64 build output is unsigned to
begin with, which Rosetta accepts; editing load commands just shouldn't leave
a stale signature behind). Finishes with a check that fails if anything still
points outside the prefix.

    bundle-deps.py PREFIX
"""
import glob
import os
import re
import shutil
import subprocess
import sys

SYSTEM_PREFIXES = ("/usr/lib/", "/System/")
# Loaded at runtime by bundled libraries rather than by Wine itself, so they
# don't show up in Wine's strings or in any load command.
EXTRA_RUNTIME_LIBS = [
    # sdl2-compat is a shim that dlopen()s SDL3, first as
    # @loader_path/libSDL3.dylib (the unversioned name, next to libSDL2).
    "libSDL3.dylib",
]
MACHO_MAGICS = {
    b"\xcf\xfa\xed\xfe", b"\xce\xfa\xed\xfe",  # thin, little-endian
    b"\xfe\xed\xfa\xcf", b"\xfe\xed\xfa\xce",  # thin, big-endian
    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",  # universal
}
LEAF_DYLIB = re.compile(rb"^lib[A-Za-z0-9_+.-]*\.dylib$")


def run(*cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def is_macho(path):
    if os.path.islink(path) or not os.path.isfile(path):
        return False
    with open(path, "rb") as f:
        return f.read(4) in MACHO_MAGICS


def dylib_id(path):
    lines = run("otool", "-D", path).splitlines()
    return lines[1].strip() if len(lines) > 1 else None


def load_deps(path):
    own = dylib_id(path)
    deps = [l.strip().split(" (")[0] for l in run("otool", "-L", path).splitlines()[1:]]
    return [d for d in deps if d != own]


def rpaths(path):
    lines = run("otool", "-l", path).splitlines()
    return [lines[i + 2].split()[1] for i, l in enumerate(lines) if l.strip() == "cmd LC_RPATH"]


def dlopen_names(path):
    """Leaf dylib names compiled into a binary as strings (dlopen targets)."""
    out = subprocess.run(["strings", "-a", path], check=True, capture_output=True).stdout
    return {s.decode() for s in out.splitlines() if LEAF_DYLIB.match(s)}


def is_system(dep):
    return dep.startswith(SYSTEM_PREFIXES)


class Bundler:
    def __init__(self, prefix):
        self.prefix = os.path.realpath(prefix)
        self.libdir = os.path.join(self.prefix, "lib")
        self.unixdir = os.path.join(self.libdir, "wine", "x86_64-unix")
        brew = run("brew", "--prefix").strip()
        self.foreign_roots = (brew + "/", "/opt/", "/usr/local/")
        self.search_dirs = [os.path.join(brew, "lib")] + sorted(glob.glob(os.path.join(brew, "opt", "*", "lib")))
        self.queue = []
        self.done = set()
        self.copied = []
        self.copied_paths = set()
        self.system_dlopen = []

    def find_foreign(self, leaf):
        for d in self.search_dirs:
            p = os.path.join(d, leaf)
            if os.path.exists(p):
                return os.path.realpath(p)
        return None

    def provide(self, leaf, hint=None):
        """Makes sure PREFIX/lib/<leaf> exists, copying it in if needed."""
        dest = os.path.join(self.libdir, leaf)
        if os.path.lexists(dest):
            return True
        src = hint if hint and os.path.isabs(hint) and os.path.exists(hint) else self.find_foreign(leaf)
        if not src:
            return False
        shutil.copy2(os.path.realpath(src), dest)
        os.chmod(dest, 0o755)
        self.copied.append((leaf, src))
        self.copied_paths.add(dest)
        self.queue.append(dest)
        return True

    def wanted_rpath(self, path):
        rel = os.path.relpath(self.libdir, os.path.dirname(path))
        return "@loader_path" if rel == "." else "@loader_path/" + rel

    def fix(self, path):
        args = []
        # The unix modules dlopen() by leaf name. Only the .so files, though:
        # the `wine` loader next to them has a custom memory layout; leave it be.
        needs_rpath = os.path.dirname(path) == self.unixdir and path.endswith(".so")

        for dep in load_deps(path):
            if is_system(dep):
                continue
            leaf = os.path.basename(dep)
            if dep.startswith("@rpath/") and leaf.endswith(".so"):
                continue  # Wine's own unix modules, resolved via @loader_path/
            if not self.provide(leaf, dep):
                sys.exit(f"error: {os.path.relpath(path, self.prefix)} needs {dep}, which could not be found")
            needs_rpath = True
            if dep != "@rpath/" + leaf:
                args += ["-change", dep, "@rpath/" + leaf]

        own = dylib_id(path)
        if own and not own.startswith("@"):
            args += ["-id", "@rpath/" + os.path.basename(own)]

        want = self.wanted_rpath(path)
        existing = rpaths(path)
        # Homebrew's own rpaths (absolute, or relative like
        # @loader_path/../../../../opt/sdl3/lib) point nowhere in the bundle.
        stale = [rp for rp in existing
                 if rp.startswith(self.foreign_roots) or (path in self.copied_paths and rp != want)]
        for rp in stale:
            args += ["-delete_rpath", rp]
        kept = [rp for rp in existing if rp not in stale]
        if path in self.copied_paths:
            needs_rpath = True  # their own dlopen()s (e.g. SDL3) resolve next to them
        if needs_rpath and want not in kept and want + "/" not in kept:
            args += ["-add_rpath", want]

        if args:
            run("install_name_tool", *args, path)
            run("codesign", "--force", "--sign", "-", path)
            print(f"fixed {os.path.relpath(path, self.prefix)}")

    def bundle(self):
        for top in ("bin", "lib", "libexec"):
            for root, dirs, files in os.walk(os.path.join(self.prefix, top)):
                # PE modules, not Mach-O
                dirs[:] = [d for d in dirs if not d.endswith("-windows")]
                self.queue += [os.path.join(root, f) for f in files if is_macho(os.path.join(root, f))]

        names = set(EXTRA_RUNTIME_LIBS)
        for so in glob.glob(os.path.join(self.unixdir, "*.so")):
            names |= dlopen_names(so)
        for leaf in sorted(names):
            if not self.provide(leaf):
                self.system_dlopen.append(leaf)

        while self.queue:
            path = self.queue.pop()
            if path not in self.done:
                self.done.add(path)
                self.fix(path)

    def verify(self):
        problems = []
        for path in sorted(self.done):
            name = os.path.relpath(path, self.prefix)
            for dep in load_deps(path):
                if dep.startswith(self.foreign_roots):
                    problems.append(f"{name} -> {dep}")
                elif dep.startswith("@rpath/") and not dep.endswith(".so"):
                    if not os.path.lexists(os.path.join(self.libdir, dep[len("@rpath/"):])):
                        problems.append(f"{name} -> {dep} (missing from lib/)")
            for rp in rpaths(path):
                if rp.startswith(self.foreign_roots) or "/opt/" in rp or "/Cellar/" in rp:
                    problems.append(f"{name} has rpath {rp}")
        return problems


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    b = Bundler(sys.argv[1])
    b.bundle()

    print(f"\nBundled {len(b.copied)} libraries:")
    for leaf, src in sorted(b.copied):
        print(f"  {leaf:32} <- {src}")
    print("dlopen() targets left to the system:", ", ".join(b.system_dlopen) or "none")
    for leaf in b.system_dlopen:
        if not os.path.exists(os.path.join("/usr/lib", leaf)):
            print(f"  note: {leaf} is not in /usr/lib either; it may only exist in the dyld shared cache")

    problems = b.verify()
    if problems:
        print("\nStill pointing outside the prefix:", *problems, sep="\n  ")
        sys.exit(1)
    print("\nAll Mach-O files resolve inside the prefix.")


if __name__ == "__main__":
    main()
