#!/usr/bin/env python3
"""Bundle the dependency closure and rewrite absolute development install names."""
import os, pathlib, shutil, subprocess
root = pathlib.Path(os.environ['SRCROOT'])
app = pathlib.Path(os.environ['TARGET_BUILD_DIR']) / os.environ['WRAPPER_NAME']
destination = app / 'Contents/Frameworks'
destination.mkdir(parents=True, exist_ok=True)
lib = root / 'Vendor/lib'
queue = [lib / n for n in ['libfreerdp3.3.dylib', 'libfreerdp-client3.3.dylib', 'libwinpr3.3.dylib']]
queue.append(lib / 'ossl-modules/legacy.dylib')
copied = set()
def dependencies(path):
    result = subprocess.check_output(['/usr/bin/otool', '-L', str(path)], text=True)
    return [line.strip().split(' (')[0] for line in result.splitlines()[1:]]
while queue:
    source = queue.pop()
    name = source.name
    if name in copied:
        continue
    copied.add(name)
    target = destination / name
    shutil.copy2(source.resolve(), target)
    target.chmod(0o755)
    deps = dependencies(target)
    subprocess.run(['/usr/bin/install_name_tool', '-id', '@rpath/' + name, str(target)], check=True)
    for dep in deps:
        if dep.startswith('/System/') or dep.startswith('/usr/lib/'):
            continue
        dependency_name = pathlib.Path(dep).name
        if dependency_name == name:
            continue
        dependency_source = lib / dependency_name
        if not dependency_source.exists():
            raise RuntimeError('Unbundled dependency: ' + dep)
        queue.append(dependency_source)
        subprocess.run(['/usr/bin/install_name_tool', '-change', dep, '@rpath/' + dependency_name, str(target)], check=True)
for name in copied:
    subprocess.run(['/usr/bin/codesign', '--force', '--sign', '-', str(destination / name)], check=True)
# Remove dependency versions left behind by an earlier build.
for path in destination.glob('*.dylib'):
    if path.name not in copied:
        path.unlink()
print('Bundled', len(copied), 'runtime libraries')
